function move_to_filled(invest, result, client, invest_path)
    trades = client.get_my_trades(symbol=invest["order"]["symbol"], orderId=invest["order"]["orderId"])

    invest["status"] = "Done"
    invest["trades"] = trades
    invest["amount"] = result["executedQty"]
    invest["value"]  = result["cummulativeQuoteQty"]
    invest["order"]  = result
    datum = split(string(today()), "-")
    new_filename = joinpath(dirname(invest_path), "filled/" * datum[1] * "/" * 
        datum[2] * "/" * invest["symbol"] * "_" * string(now()) * ".json")
    !isdir(dirname(new_filename)) ? mkpath(dirname(new_filename)) : ""
    rm(invest_path)
    open(new_filename, "w") do f
        JSON.print(f, invest, 4)
    end
end
export move_to_filled