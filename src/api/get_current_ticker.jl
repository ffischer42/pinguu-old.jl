function get_current_ticker(client, config; use_api=false, ticker_dir="/home/felix/pinguu/wp_data/ticker/")
    if use_api
        ticker = client.get_ticker(symbol=config["symbol"])["lastPrice"]
    else
        ticker_data = JSON.parsefile(joinpath(ticker_dir, config["symbol"] * "_kline_1m_candle.json"));
        ticker = Pinguu.price2string(ticker_data[end][end], config["sell_precision"])
    end
    return ticker, parse(Float64, ticker)
end
export get_current_ticker