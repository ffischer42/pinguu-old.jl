function place_order_command(k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    @info("test")
    sleep(2)
    t = try Pinguu.examine_order(closed_orders[id_str], id_str, client, config, bot_path)
    catch
        open(joinpath(bot_path, "trigger.json"), "w") do f
            JSON.print(f, Dict(), 4)
        end
        @info("examine_order failed")
        return nothing
    end
    qty = floor(t["use_vol"], digits=config["precision"])
    price = Pinguu.price2string(round((abs(t["current_profit"]) / qty * 
        (1 + fees["maker"] + 
            parse(Float64, config["take_profit"])/100)
            * t["price_correction"]), digits=config["sell_precision"]), config["sell_precision"])

    account = client.get_account()["balances"];
    new = 0
    for bal in account
        if bal["asset"] == config["farm_coin"]
            if parse(Float64, bal["free"]) <= qty
                new = parse(Float64, bal["free"])
            end
        end
    end
    if qty > new && new != 0
        reference = qty * parse(Float64, price)
        qty = floor(new, digits=config["precision"])
        price = Pinguu.price2string(round(reference / qty, digits=config["sell_precision"]), config["sell_precision"])
    end
    @info("Try to place sell")
    @info("Qty  = $qty")
    @info("Price = " * price)
    
    order = try client.order_limit_sell(
        symbol=config["symbol"],
        quantity=qty,
        price=price);
        catch 
        nothing
    end
    if order !== nothing
        order["time"] = string(now())
        open_orders["SELL"][k] = order
        @info("Success")
    else
        v["fail"] = 1
        @info("Failed.. Placing another trigger")
    end
    open(joinpath(bot_path, "open_orders.json"), "w") do f
        JSON.print(f, open_orders, 4)
    end
    open(joinpath(bot_path, "trigger.json"), "w") do f
        JSON.print(f, Dict(), 4)
    end
end
export place_order_command