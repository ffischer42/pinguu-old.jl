

function stop_order(order, id, config, closed_orders, bot_path, client)
    #
    ## Cancel order
    result = try client.cancel_order(
        symbol=order["symbol"],
        orderId=order["orderId"])
    catch
        nothing
    end
    
    #
    ## Cancel order did not work, try it next round again
    if result == nothing 
        return nothing
    end
    
    #
    ## Order was partially executed
    if parse(Float64, result["executedQty"]) != 0.0
        id_str = split(id, "_")[end]
        closed_orders[id_str]["SELL-" * lpad(rand(1:1:100000), 6, "0")] = deepcopy(result);
        open(joinpath(bot_path, "closed_orders.json"), "w") do f
            JSON.print(f, closed_orders, 4)
        end
    end

    #
    ## Create new temp order
    new = Dict()
    new["price"] = order["price"]
    new["origQty"] = string(parse(Float64, order["origQty"]) - parse(Float64, order["executedQty"]))
    new["executedQty"] = order["executedQty"]
    new["symbol"] = order["symbol"]
    new["status"] = "stopped"
    new["side"] = order["side"]
    new["type"] = order["type"]
    return new
end
export stop_order

function revive_order(order, id, config, closed_orders, bot_path, client)
    qty = floor(parse(Float64, order["origQty"]), digits=config["precision"])
    if order["side"] == "SELL"
        result = try client.order_limit_sell(
            symbol=order["symbol"],
            quantity=qty,
            price=order["price"]);
            catch 
            nothing
        end
    else
        result = try client.order_limit_buy(
            symbol=order["symbol"],
            quantity=qty,
            price=order["price"]);
            catch 
            nothing
        end
    end
    
    return result    
end
export revive_order


function check_open_sell!(config, open_orders, closed_orders, bot_path, client, usr)
    if length(open_orders["SELL"]) > 0
        if !haskey(config, "current_fees")
            fees = client.get_trade_fee(symbol=config["symbol"])["tradeFee"][1]
        else
            fees = config["current_fees"][config["symbol"]]
        end
    end
    #
    ## Check for "cancel order" !
    for (k,v) in open_orders["SELL"]
        id_str = split(k, "_")[end]
        if v["status"] == "cancel order"
            #
            ## Get order status
            if haskey(v, "orderId")
                tmp_sell = try client.get_order(
                    symbol=config["symbol"],
                    orderId=v["orderId"])
                    catch 
                    nothing
                end
                if tmp_sell !== nothing
                    if !(tmp_sell["status"] in [client.ORDER_STATUS_FILLED, client.ORDER_STATUS_CANCELED])
                        #
                        ## Cancel Order
                        sleep(0.5)
                        tmp_sell = try client.cancel_order(
                            symbol=config["symbol"],
                            orderId=v["orderId"])
                        catch
                            nothing
                        end
                    end
                    if tmp_sell !== nothing && tmp_sell["status"] in [client.ORDER_STATUS_FILLED, client.ORDER_STATUS_CANCELED]
                        if parse(Float64, tmp_sell["executedQty"]) > 0
                            random_id_str = "SELL-" * lpad(rand(1:1:10000), 5, "0")
                            while haskey(closed_orders[id_str], random_id_str)
                                random_id_str = "SELL-" * lpad(rand(1:1:10000), 5, "0")
                            end
                            closed_orders[id_str][random_id_str] = tmp_sell
                            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                                JSON.print(f, closed_orders, 4)
                            end
                        end
                        delete!(open_orders, k)
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end
                    else
                        open(joinpath(bot_path, "trigger.json"), "w") do f
                            JSON.print(f, Dict(), 4)
                        end
                        return open_orders, closed_orders
                    end
                else
                    open(joinpath(bot_path, "trigger.json"), "w") do f
                        JSON.print(f, Dict(), 4)
                    end
                    return open_orders, closed_orders
                end
            else
                #
                ## No orderId -> no order
                delete!(open_orders, k)
                open(joinpath(bot_path, "open_orders.json"), "w") do f
                    JSON.print(f, open_orders, 4)
                end
            end
        end
    end
    
    
    for (k,v) in open_orders["SELL"]
        #
        # If Pinguu is STOPPED!
        #
        if config["status"] == "stopped"
            if v["status"] == "stopped"
                @info("Order is on hold")
            else
                # Stop order for now
                @info("Stopping order")
                order = stop_order(v, k, config, closed_orders, bot_path, client)
                if order !== nothing
                    #
                    ## Change v with temp order
                    open_orders["SELL"][k] = order
                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                else
                    @info("Cancelling order failed. Will try again soon.")
                    open(joinpath(bot_path, "trigger.json"), "w") do f
                        JSON.print(f, Dict(), 4)
                    end
                end                
            end
        else
            #
            # Pinguu running as usual
            #
            if v["status"] == "stopped" && config["status"] == "active"
                order = revive_order(v, k, config, closed_orders, bot_path, client)
                
                
                if order !== nothing
                    open_orders["SELL"][k] = order
                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                    v = deepcopy(order)
                else
                    @info("Reviving order failed. Will try again soon.")
                    open(joinpath(bot_path, "trigger.json"), "w") do f
                        JSON.print(f, Dict(), 4)
                    end
                    continue
                end
            end
            
            
            if v["status"] != "place order"
                skip = false
                tmp = try client.get_order(
                    symbol=config["symbol"],
                    orderId=v["orderId"])
                    catch 
                    @info("Skipped..")
                    sleep(0.75)
                    open(joinpath(bot_path, "trigger.json"), "w") do f
                        JSON.print(f, Dict(), 4)
                    end
                    skip = true
                end

                if !skip
                    id_str = split(k, "_")[end]
                    if tmp["status"] == client.ORDER_STATUS_FILLED
                        !(id_str in keys(closed_orders)) ? closed_orders[id_str] = Dict() : ""
                        tmp["time"] = string(now())

                        delete!(open_orders["SELL"], k)
                        for (k2, v2) in open_orders["BUY"]
                            if split(k2, "_")[end] == id_str
                                sleep(0.2)
                                tmp_buy = try client.get_order(
                                    symbol=config["symbol"],
                                    orderId=v2["orderId"])
                                catch 
                                    nothing
                                end

                                if tmp_buy !== nothing
                                    if !(tmp_buy["status"] in [client.ORDER_STATUS_FILLED, client.ORDER_STATUS_CANCELED])
                                        sleep(0.5)
                                        result = try client.cancel_order(
                                            symbol=config["symbol"],
                                            orderId=v2["orderId"])
                                        catch
                                            nothing
                                        end
                                        if result !== nothing
                                            delete!(open_orders["BUY"], k2)
                                        else
                                            open_orders["BUY"][k2]["status"] = "cancel"
                                        end
                                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                                            JSON.print(f, open_orders, 4)
                                        end
                                    else
                                        delete!(open_orders["BUY"], k2)
                                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                                            JSON.print(f, open_orders, 4)
                                        end
                                    end
                                    if parse(Float64, tmp_buy["executedQty"]) > 0
                                        closed_orders[id_str][k2] = tmp_buy
                                        open(joinpath(bot_path, "closed_orders.json"), "w") do f
                                            JSON.print(f, closed_orders, 4)
                                        end
                                    end
                                else
                                    open_orders["BUY"][k2]["status"] = "cancel"
                                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                                        JSON.print(f, open_orders, 4)
                                    end
                                end
                            end
                        end
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end
                        qty = 0
                        net_qty = 0
                        val = 0
                        for (k2,v2) in closed_orders[id_str]
                            v2["side"] == "BUY" ? qty += parse(Float64, v2["executedQty"]) : ""
                            v2["side"] == "BUY" ? net_qty += parse(Float64, v2["executedQty"]) : net_qty -= parse(Float64, v2["executedQty"])
                            v2["side"] == "BUY" ? val -= parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 + fees["taker"]) : val += parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 - fees["maker"]) 
                        end

                        if val < 0 && val + parse(Float64, tmp["cummulativeQuoteQty"]) < 0
                            #
                            ## If there was an extra buy executed
                            closed_orders[id_str]["SELL-" * lpad(rand(1:1:100000), 6, "0")] = deepcopy(tmp);

                            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                                JSON.print(f, closed_orders, 4)
                            end
                            #
                            ## Create new sell
                            if abs(val) > config["min_qty"]
                                #
                                ## qty is high enough to be sold
                                new_qty = floor(net_qty, digits=config["precision"])
                                new_price = Pinguu.price2string(floor(abs(val)/net_qty * (1 + parse(Float64, config["take_profit"])/100), digits=config["sell_precision"]), config["sell_precision"])
                                sleep(0.2)
                                order = try client.order_limit_sell(
                                    symbol=config["symbol"],
                                    quantity=new_qty,
                                    price=new_price);
                                    catch 
                                    nothing
                                end
                                new_id = "SELL_" * id_str
                                if order !== nothing
                                    order["time"] = string(now())
                                    open_orders["SELL"][new_id] = order
                                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                                        JSON.print(f, open_orders, 4)
                                    end
                                    #
                                    ## Place new buy
                                    extra_iteration = 0
                                    for (k2,v2) in closed_orders[id_str]
                                        if length(split(k2, "SELL")) < 2
                                            if parse(Int64, split(split(k2, "_")[1], "-")[end]) > extra_iteration
                                                extra_iteration = parse(Int64, split(split(k2, "_")[1], "-")[end])
                                            end
                                        end
                                    end
                                    extra_iteration += 1
                                    if extra_iteration <= parse(Float64, config["extra_order_count"])                                
                                        new_price = Pinguu.price2string(round(parse(Float64, new_price) * (1 - config["extra_order_step"]), digits=config["sell_precision"]), config["sell_precision"])
                                        
                                        quant = floor(config["order_volume"] * (config["extra_order_martingale"])^(extra_iteration + 1) / parse(Float64, new_price), digits=config["precision"])

                                        new_buy = Dict()
                                        new_buy["status"] = "place order"
                                        new_buy["origQty"] = quant
                                        new_buy["price"] = new_price
                                        new_buy_id = "EXTRA-" * string(extra_iteration) * "_" * id_str
                                        open_orders["BUY"][new_buy_id] = new_buy
                                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                                            JSON.print(f, open_orders, 4)
                                        end
                                    end
                                else
                                    #
                                    ## If new sell could not be placed
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
                            else
                                #
                                ## qty is NOT high enough to be sold
                                new_price = Pinguu.price2string(floor(abs(val)/net_qty * (1 + parse(Float64, config["take_profit"])/100), digits=config["sell_precision"]), config["sell_precision"])

                                extra_iteration = 0
                                for (k2,v2) in closed_orders[id_str]
                                    if length(split(k2, "SELL")) < 2
                                        if parse(Int64, split(split(k2, "_")[1], "-")[end]) > extra_iteration
                                            extra_iteration = parse(Int64, split(split(k2, "_")[1], "-")[end])
                                        end
                                    end
                                end
                                extra_iteration += 1
                                if extra_iteration <= parse(Float64, config["extra_order_count"])                                
                                    new_price = Pinguu.price2string(round(parse(Float64, new_price) * (1 - config["extra_order_step"]), digits=config["sell_precision"]), config["sell_precision"])
                                    quant = floor(config["order_volume"] * (config["extra_order_martingale"])^(extra_iteration + 1) / parse(Float64, new_price), digits=config["precision"])

                                    new_buy = Dict()
                                    new_buy["status"] = "place order"
                                    new_buy["origQty"] = quant
                                    new_buy["price"] = new_price
                                    new_buy_id = "EXTRA-" * string(extra_iteration) * "_" * id_str
                                    open_orders["BUY"][new_buy_id] = new_buy
                                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                                        JSON.print(f, open_orders, 4)
                                    end
                                end
                            end
                        else
                            #
                            ####################################################################
                            #
                            #
                            ## If everything went well and the profit is positive
                            sell_id = !haskey(closed_orders[id_str], "SELL") ? "SELL" : "SELL-" * lpad(rand(1:1:100000), 6, "0")
                            closed_orders[id_str][sell_id] = deepcopy(tmp);


                            open(joinpath(bot_path, "closed_order-" * id_str * ".json"), "w") do f
                                JSON.print(f, closed_orders[id_str], 4)
                            end

                            try for (k5,v5) in closed_orders
                                    if DateTime(split(k5, "--")[end]) < now() - Day(42)
                                        delete!(closed_orders, k5)
                                    end
                                end
                            catch;
                            end

                            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                                JSON.print(f, closed_orders, 4)
                            end
                        end
                        #
                        ####################################################################
                        #

                    elseif tmp["status"] == client.ORDER_STATUS_CANCELED
                        delete!(open_orders["SELL"], k)
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end
                        if parse(Float64, tmp["executedQty"]) > 0
                            closed_orders[id_str]["SELL-" * lpad(rand(1:1:100000), 6, "0")] = tmp
                            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                                JSON.print(f, closed_orders, 4)
                            end
                        end
                    elseif tmp["status"] != v["status"]
                        open_orders["SELL"][k] = tmp
                        open_orders["SELL"][k]["time"] = string(now())
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end
                    end
                end
            else
                id_str = split(k, "_")[end]
                place_order_command(k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            end
        end
    end
    sleep(0.25)
    return open_orders, closed_orders
end


function check_open_buy!(config, open_orders, closed_orders, bot_path, client, usr)
    if length(open_orders["BUY"]) == 0
        return open_orders, closed_orders
    end
    fees = haskey(config, "current_fees") ? config["current_fees"][config["symbol"]] : client.get_trade_fee(symbol=config["symbol"])["tradeFee"][1]
    
    for (k,v) in open_orders["BUY"]
        id_str = split(k, "_")[end]
        ##------------------------------------------------------------------------##
        ## Pinguu in STOP mode----------------------------------------------------##
        ##------------------------------------------------------------------------##
        if config["status"] == "stopped" && v["status"] != "stopped"
            Pinguu.check_stopped_orders(k, v, config, open_orders, closed_orders, bot_path, client, usr)
            continue
        elseif config["status"] == "active" && v["status"] == "stopped"
            Pinguu.check_orders_to_revive(k, v, config, open_orders, closed_orders, bot_path, client, usr)
            continue
        end
        ##------------------------------------------------------------------------##
        ## PLACE ORDER command----------------------------------------------------##
        ##------------------------------------------------------------------------##
        if v["status"] == "place order"
            Pinguu.place_buy_order_command(k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end
        ##------------------------------------------------------------------------##
        ## Cancel BUY-------------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if v["status"] == "cancel"
            Pinguu.cancel_buy(k, v, id_str, config, open_orders, closed_orders, bot_path, client)
            continue
        end
                
        ##------------------------------------------------------------------------##
        ## Load BUY updates-------------------------------------------------------##
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
        ## BUY Filled-------------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] == client.ORDER_STATUS_FILLED || v["status"] == "continue" || parse(Float64, tmp["executedQty"]) == parse(Float64, tmp["origQty"])
            Pinguu.buy_executed(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end
        ##------------------------------------------------------------------------##
        ## BUY now----------------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if v["status"] == "buy now"
            @info("Buy now")
            Pinguu.buy_now(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## Order was canceled-----------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] == client.ORDER_STATUS_CANCELED && parse(Float64, tmp["executedQty"]) == 0
            delete!(open_orders["BUY"], k)
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## Order partially filled-------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] == client.ORDER_STATUS_PARTIALLY_FILLED && v["status"] != tmp["status"]
            v = deepcopy(tmp)
            v["time"] = string(now())
            v["partial_time"] = string(now())
            open_orders["BUY"][k] = v
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
            continue
        end
        if parse(Float64, tmp["executedQty"]) != 0 && parse(Float64, tmp["executedQty"]) != parse(Float64, tmp["origQty"]) && haskey(v, "partial_time")
            Pinguu.partially_order(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees, 3)
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## Status changed---------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] != v["status"]
            tmp["time"] = string(now())
            open_orders["BUY"][k] = tmp
            if haskey(v, "partial_time")
                open_orders["BUY"][k]["partial_time"] = v["partial_time"]
            end
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## Check first order------------------------------------------------------##
        ##------------------------------------------------------------------------##
        if tmp["status"] == "NEW" && split(k, "_")[1] == "EXTRA-0" && parse(Float64, tmp["executedQty"]) == 0.0
            Pinguu.first_order_takes_too_long(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees, 1)
            continue
        end
        
        ##------------------------------------------------------------------------##
        ## Check current closed orders - performance------------------------------##
        ##------------------------------------------------------------------------##
        try Pinguu.check_ongoing_closed(id_str, config, closed_orders, bot_path, client)
            catch;
        end

        ##------------------------------------------------------------------------##
        ## Check if the corresponding sell is placed------------------------------##
        ##------------------------------------------------------------------------##
        extra_iteration = parse(Int64, split(split(k, "_")[1], "-")[2])
        check_sell = true
        if extra_iteration > 0
            for (k_sell, v_sell) in open_orders["SELL"]
                if split(k_sell, "_")[end] == id_str
                    check_sell = false
                end
            end
            #
            ## PureEMA bot:
            if check_sell && haskey(config, "pureEMA")
                check_sell = config["pureEMA"] == 1 ? false : true
            end
            if check_sell
                closed_order = closed_orders[id_str]
                @info("Check why there is no sell!")
                open(joinpath(bot_path, "trigger.json"), "w") do f
                    JSON.print(f, Dict(), 4)
                end
                Pinguu.check_why_there_is_no_sell(closed_order, id_str, open_orders, client, config, bot_path)
            end
        end
    end
    return open_orders, closed_orders
end
   