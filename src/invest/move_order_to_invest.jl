function move_order_to_invest(orderId, client, user_id, symbol)
    order = client.get_order(symbol=symbol, orderId=orderId)
    trades = client.get_my_trades(symbol=order["symbol"], orderId=order["orderId"])
    
    if order["price"] == "0.00000000"
        order["price"] = string(parse(Float64, order["cummulativeQuoteQty"]) / parse(Float64, order["executedQty"]))
    end
    farm_coin = split(order["symbol"], "EUR")[1]
    base_coin = "EUR"
    invest = Dict(
        "amount" => order["origQty"],
        "farm_coin" => farm_coin,
        "base_coin" => base_coin,
        "mode" => "now",
        "t" => string(unix2datetime(order["time"]/1000)),
        "symbol" => order["symbol"],
        "value" => order["cummulativeQuoteQty"],
        "order" => order,
        "trades" => trades,
        "status" => "Done"
    )
    
    y, m = split(split(string(invest["t"]), "T")[1], "-")[1:2]
    file = string(joinpath(Pinguu.base_dir[2:end], "invest/users/$user_id/filled/", y, "/", m, "/", invest["symbol"], "_", invest["t"], ".json"))
    !isdir(dirname(file)) ? mkpath(dirname(file)) : ""
    open(file, "w") do f
        JSON.print(f, invest, 4)
    end
    return invest
end
export move_order_to_invest