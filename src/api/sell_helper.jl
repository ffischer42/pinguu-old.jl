
function place_sell_order_command(k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    t = try Pinguu.examine_order(closed_orders[id_str], id_str, client, config)
    catch
        return nothing
    end
    qty = floor(t["use_vol"], digits=config["precision"])
    price = round((abs(t["current_profit"]) / qty * 
        (1 + fees["maker"] + 
            parse(Float64, config["take_profit"])/100)
            * t["price_correction"]), digits=config["sell_precision"])
    price = Pinguu.price2string(price, config["sell_precision"])

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
        price = Pinguu.price2string(reference / qty, config["sell_precision"])
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
export place_sell_order_command   

function sell_filled(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    #
    ## Check if id is in closed_orders
    !(id_str in keys(closed_orders)) ? closed_orders[id_str] = Dict() : ""
    tmp["time"] = string(now())
    #
    ## Delete Sell from open_orders
    delete!(open_orders["SELL"], k)
    #
    ## Cancel all related open BUYs
    for (k2, v2) in open_orders["BUY"]
        if split(k2, "_")[end] == id_str
            sleep(0.25)
            #
            ## Load order status
            tmp_buy = try client.get_order(
                symbol=config["symbol"],
                orderId=v2["orderId"])
            catch 
                nothing
            end
            #
            ## Update open/closed orders
            if tmp_buy !== nothing
                if !(tmp_buy["status"] in [client.ORDER_STATUS_FILLED, client.ORDER_STATUS_CANCELED])
                    sleep(0.25)
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
                else
                    delete!(open_orders["BUY"], k2)
                end
                if parse(Float64, tmp_buy["executedQty"]) > 0
                    closed_orders[id_str][k2] = tmp_buy
                end
            else
                open_orders["BUY"][k2]["status"] = "cancel"
            end
        end
    end
    #
    ## Write to files
    open(joinpath(bot_path, "closed_orders.json"), "w") do f
        JSON.print(f, closed_orders, 4)
    end
    open(joinpath(bot_path, "open_orders.json"), "w") do f
        JSON.print(f, open_orders, 4)
    end
    qty = 0     # Totel volume
    net_qty = 0 # Total worth
    val = 0     # Value in base coin
    for (k2,v2) in closed_orders[id_str]
        v2["side"] == "BUY" ? qty += parse(Float64, v2["executedQty"]) : ""
        v2["side"] == "BUY" ? net_qty += parse(Float64, v2["executedQty"]) : net_qty -= parse(Float64, v2["executedQty"])
        v2["side"] == "BUY" ? val -= parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 + fees["taker"]) : val += parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 - fees["maker"]) 
    end
    #
    ## Check if this was the only SELL
    if val < 0 && val + parse(Float64, tmp["cummulativeQuoteQty"]) < 0
        #
        ## If there was an extra SELL executed
        rnd_id = "SELL-" * lpad(rand(1:1:1000), 6, "0")
        while rnd_id in keys(closed_orders[id_str])
            rnd_id = "SELL-" * lpad(rand(1:1:1000), 6, "0")
        end
        closed_orders[id_str][rnd_id] = deepcopy(tmp);
        open(joinpath(bot_path, "closed_orders.json"), "w") do f
            JSON.print(f, closed_orders, 4)
        end
        #
        ## Create new sell
        if abs(val) > config["min_qty"]
            #
            ## qty is high enough to be sold
            new_qty = floor(net_qty, digits=config["precision"])
            new_price = Pinguu.price2string(abs(val)/net_qty * (1 + parse(Float64, config["take_profit"])/100), config["sell_precision"], round_up=true)
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
                    new_price = Pinguu.price2string(parse(Float64, new_price) * (1 - config["extra_order_step"]), config["sell_precision"])
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
            new_price = Pinguu.price2string(abs(val)/net_qty * (1 + parse(Float64, config["take_profit"])/100), digits=config["sell_precision"])

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
                new_price = string(round(parse(Float64, new_price) * (1 - config["extra_order_step"]), digits=config["sell_precision"]))
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
end
export sell_filled

function sell_canceled(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
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
end
export sell_canceled

function sell_status_changed(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    open_orders["SELL"][k] = tmp
    open_orders["SELL"][k]["time"] = string(now())
    open(joinpath(bot_path, "open_orders.json"), "w") do f
        JSON.print(f, open_orders, 4)
    end
end
export sell_status_changed


function cancel_sell(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    tmp_sell = try client.cancel_order(
        symbol=config["symbol"],
        orderId=v["orderId"])
    catch
        nothing
    end
    if tmp_sell !== nothing || tmp["status"] == client.ORDER_STATUS_FILLED || tmp["status"] == client.ORDER_STATUS_CANCELED
        if parse(Float64, v2["executedQty"]) > 0
            closed_orders[id_str]["SELL-" * lpad(rand(1:1:10000), 5, "0")] = result
            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                JSON.print(f, closed_orders, 4)
            end
        end
        delete!(open_orders["SELL"], k2)
    else
        @info("Cancel SELL failed")
    end
end
export cancel_sell