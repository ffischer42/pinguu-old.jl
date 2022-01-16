function place_invest(invest, client, invest_path)
    #
    ## Get Symbol Info
    buy_precision, sell_precision, min_qty, stepSize, tickSize = Pinguu.get_precision(client, invest["symbol"])

    #
    ## Get price/qty
    if haskey(invest, "price")
        current = invest["price"]
        ## ADD FORMAT CHECK
    else
        sleep(0.5)
        current = client.get_ticker(symbol=invest["symbol"])["lastPrice"];
    end
    current_val = parse(Float64, current)
    #
    ## Apply mode
    if invest["mode"] == "falling"
        current_val = current_val * (1 - parse(Float64, invest["fall_by"])/100)
        current = Pinguu.price2string(current_val, sell_precision, round_up=false)
    end
    qty = floor(parse(Float64, invest["amount"]) / current_val, digits=buy_precision)
    
    if qty * current_val <= min_qty
        min_val = min_qty + ceil(min_qty - qty * current_val, digits=buy_precision)
        invest["status"] = "Wrong QTY"
        invest["message"] = "Minimum von $min_qty nicht erreicht. Klicke auf Stornieren und versuche es mit einem höheren Kaufwert erneut.<br> Minimum: $min_val €";
        open(invest_path, "w") do f
            JSON.print(f, invest, 4)
        end
        return invest
    end
    @info("Price: " * current)
    @info("QTY: $qty")
    sleep(0.5)
    order = client.order_limit_buy(
        symbol=invest["symbol"],
        quantity=qty,
        price=current)

    if order !== nothing
        invest["order"] = order
        invest["status"] = "Order placed"
    else
        invest["status"] = "Placing order failed"
    end   
    
    return invest
end
export place_invest