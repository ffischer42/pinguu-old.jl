function check_why_there_is_no_sell(closed_order, id_str, open_orders, client, config, bot_path)
    t = Pinguu.examine_order(closed_order, id_str, client, config, bot_path)
    fees = config["current_fees"][config["symbol"]]
    new_id    = "SELL_" * id_str 
    new_quant = floor(t["use_vol"], digits=config["precision"])
    
    new_price = Pinguu.price2string(round((abs(t["current_profit"]) / new_quant * 
        (1 + fees["maker"] + 
            parse(Float64, config["take_profit"])/100)
            * t["price_correction"]), digits=config["sell_precision"]), config["sell_precision"])
    if abs(t["current_profit"]) > config["min_qty"]
        order = try client.order_limit_sell(
            symbol=config["symbol"],
            quantity=new_quant,
            price=new_price);
            catch 
            nothing
        end
        open(joinpath(bot_path, "trigger.json"), "w") do f
            JSON.print(f, Dict(), 4)
        end
        @info(order)
        sleep(2)
        if order !== nothing
            order["time"] = string(now())
            open_orders["SELL"][new_id] = order
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
        else
            open_orders["SELL"][new_id] = Dict()
            open_orders["SELL"][new_id]["origQty"] = new_quant
            open_orders["SELL"][new_id]["price"]   = new_price
            open_orders["SELL"][new_id]["status"]  = "place order"
            open_orders["SELL"][new_id]["time"]    = string(now())
            open_orders["SELL"][new_id]["fail"]    = 0
            open_orders["SELL"][new_id]["if_fail"] = new_quant - 1/10^config["precision"]           

            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
        end
    end
end
export check_why_there_is_no_sell