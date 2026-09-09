-- Inofficial Binance Extension (www.binance.com) for MoneyMoney
-- Fetches balances from Binance API and returns them as securities
--
-- Username: Binance API Key
-- Password: Binance API Secret
--
-- Copyright (c) 2017 Johannes Heck
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

WebBanking {
  version     = 1.5,
  url         = "https://api.binance.com/api",
  description = "Fetch balances from Binance API and list them as securities",
  services    = { "Binance Account" },
}

local apiKey
local apiSecret
local balances
local currency

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Binance Account"
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
  apiKey = username
  apiSecret = password
  currency = "EUR"
end

function ListAccounts (knownAccounts)
  local account = {
    name = market,
    accountNumber = "Binance Account",
    currency = currency,
    portfolio = true,
    type = "AccountTypePortfolio"
  }

  return {account}
end

function RefreshAccount (account, since)
  balances = queryPrivate("account")["balances"]
  mergeEarnings()

  local pricesBySymbol = {}
  for _, ticker in ipairs(queryPublic("ticker/price")) do
    pricesBySymbol[ticker["symbol"]] = tonumber(ticker["price"])
  end

  local s = {}
  for key, value in pairs(balances) do
    if tonumber(value["free"]) > 0 then
      s[#s+1] = {
        name = value["asset"],
        market = market,
        currency = nil,
        quantity = value["free"],
        price = priceInEur(value["asset"], pricesBySymbol),
      }
    end
  end

  return {securities = s}
end

-- Binance does not list a EUR pair for every asset, so fall back to
-- converting via USDT or BTC, whichever pair is available.
function priceInEur(asset, pricesBySymbol)
  if asset == "EUR" then
    return 1
  end

  local direct = pricesBySymbol[asset .. "EUR"]
  if direct then
    return direct
  end

  local usdt = pricesBySymbol[asset .. "USDT"]
  local eurUsdt = pricesBySymbol["EURUSDT"]
  if usdt and eurUsdt then
    return usdt / eurUsdt
  end

  local btc = pricesBySymbol[asset .. "BTC"]
  local btcEur = pricesBySymbol["BTCEUR"]
  if btc and btcEur then
    return btc * btcEur
  end

  return 0
end

function mergeEarnings()
  for ldKey, ldValue in pairs(balances) do
    if string.sub(ldValue["asset"], 1, 2) == "LD" then
      asset = string.sub(ldValue["asset"], 3, string.len(ldValue["asset"]))
      for assetKey, assetValue in pairs(balances) do
        if assetValue["asset"] == asset then
          balances[assetKey]["free"] = tonumber(assetValue["free"]) + tonumber(ldValue["free"])
          balances[assetKey]["locked"] = tonumber(assetValue["locked"]) + tonumber(ldValue["locked"])
          balances[ldKey] = nil
        end
      end
      if balances[ldKey] ~= nil then
        ldValue["asset"] = asset
      end
    end
  end
end

function EndSession ()
end

function bin2hex(s)
 return (s:gsub(".", function (byte)
   return string.format("%02x", string.byte(byte))
 end))
end

function queryPrivate(method)
  local path = string.format("/%s/%s", "v3", method)
  local timestamp = string.format("%d", MM.time() * 1000)
  local params = "timestamp=" .. timestamp
  local apiSign = MM.hmac256(apiSecret, params)

  local headers = {}
  headers["X-MBX-APIKEY"] = apiKey

  connection = Connection()
  content = connection:request("GET", url .. path .. "?" .. params .. "&signature=" .. bin2hex(apiSign), nil, nil, headers)

  json = JSON(content)

  return json:dictionary()
end

function queryPublic(method)
  local path = string.format("/%s/%s", "v3", method)

  connection = Connection()
  content = connection:request("GET", url .. path)
  json = JSON(content)

  return json:dictionary()
end
