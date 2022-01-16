function check_open_sell(config, open_orders, closed_orders, bot_path, client, usr)
    if length(open_orders["SELL"]) == 0
        return open_orders, closed_orders
    end
    fees = haskey(config, "current_fees") ? config["current_fees"][config["symbol"]] : client.get_trade_fee(symbol=config["symbol"])["tradeFee"][1]
    
    #
    ## Go through all open SELL orders
    for (k,v) in open_orders["SELL"]
        id_str = split(k, "_")[end]
        ##------------------------------------------------------------------------##
        ## Pinguu in STOP mode----------------------------------------------------##
        ##------------------------------------------------------------------------##
        if config["status"] == "stopped" && v["status"] != "stopped"
            check_stopped_orders(k, v, config, open_orders, closed_orders, bot_path, client, usr)
            continue
        elseif config["status"] == "active" && v["status"] == "stopped"
            check_orders_to_revive(k, v, config, open_orders, closed_orders, bot_path, client, usr)
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## PLACE ORDER command----------------------------------------------------##
        ##------------------------------------------------------------------------##
        if v["status"] == "place order"
            place_sell_order_command(k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## Load SELL updates------------------------------------------------------##
        ##------------------------------------------------------------------------##
        tmp = try client.get_order(
            symbol=config["symbol"],
            orderId=v["orderId"])
        catch 
            @info("Skipped..")
            open(joinpath(bot_path, "trigger.json"), "w") do f
                JSON.print(f, Dict(), 4)
            end
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## SELL Filled------------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] == client.ORDER_STATUS_FILLED
            sell_filled(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end

        ##------------------------------------------------------------------------##
        ## SELL Canceled----------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] == client.ORDER_STATUS_CANCELED
            sell_canceled(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## Cancel SELL------------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] == "cancel order"
            cancel_sell(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end

        ##------------------------------------------------------------------------##
        ## SELL status changed----------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] != v["status"]
            sell_status_changed(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end
    end
    return open_orders, closed_orders
end
export check_open_sell