function place_first_grid_order!(current, ticker, config, open_orders, bot_path, client, usr)
    @info("NEW order found!")
    id_str = open_orders["NEW"]["trigger"] * "--" * string(now())
    quant = ceil(config["order_volume"] / current, digits=config["precision"])
    if config["precision"] < 1
        quant = string(Int(quant))
    end
    order = try client.order_limit_buy(
        symbol=config["symbol"],
        quantity=quant,
        price=ticker);
    catch
        @info("order_limit_buy failed")
        nothing
    end
    if order !== nothing
        open_orders["BUY"]["EXTRA-0_" * id_str] = order
        open_orders["NEW"] = Dict()
        open(joinpath(bot_path, "open_orders.json"), "w") do f
            JSON.print(f, open_orders, 4)
        end
        p = Dict()
        p["ticker"] = ticker
        create_notification("new cycle", config, usr, params = p)
    end
    return open_orders
end
export place_first_grid_order!






function place_buy_order_command(k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    quant = round(v["origQty"], digits=config["precision"])
    new_id = k
    if v["price"] != "market"
        new_price = Pinguu.price2string(parse(Float64, v["price"]), config["sell_precision"])
        order = try client.order_limit_buy(
            symbol= config["symbol"],
            quantity=quant,
            price=new_price);
            catch 
            nothing
        end
    else
        order = try client.order_market_buy(
            symbol= config["symbol"],
            quantity=quant);
            catch 
            nothing
        end
    end
    if order !== nothing
        order["time"] = string(now())
        open_orders["BUY"][new_id] = order
    else
        open_orders["BUY"][new_id] = Dict()
        open_orders["BUY"][new_id]["origQty"] = quant
        open_orders["BUY"][new_id]["price"]   = new_price
        open_orders["BUY"][new_id]["status"]  = "place order"
        open_orders["BUY"][new_id]["time"]    = string(now())
    end
    open(joinpath(bot_path, "open_orders.json"), "w") do f
        JSON.print(f, open_orders, 4)
    end
    open(joinpath(bot_path, "trigger.json"), "w") do f
        JSON.print(f, Dict(), 4)
    end
end
export place_buy_order_command

function buy_executed(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    #
    ## Cancel order, if not done yet
    if tmp["status"] != client.ORDER_STATUS_FILLED && tmp["status"] != client.ORDER_STATUS_CANCELED
        result = try client.cancel_order(
            symbol=config["symbol"],
            orderId=tmp["orderId"])
        catch
            nothing
        end
        if result == nothing
            return nothing
        end
    end
    extra_iteration = parse(Int64, split(split(k, "_")[1], "-")[2])
    #
    ## Move to closed_orders
    !(id_str in keys(closed_orders)) ? closed_orders[id_str] = Dict() : ""
    tmp["time"] = string(now())
    closed_orders[id_str][split(k, "_")[1]] = deepcopy(tmp);
    open(joinpath(bot_path, "closed_orders.json"), "w") do f
        JSON.print(f, closed_orders, 4)
    end
    #
    ## Remove from open_orders
    delete!(open_orders["BUY"], k)
    open(joinpath(bot_path, "open_orders.json"), "w") do f
        JSON.print(f, open_orders, 4)
    end
    #
    ## Place EXTRA
    new_id = "EXTRA-" * string(extra_iteration + 1) * "_" * id_str
    
    last_price = parse(Float64, tmp["price"]) == 0.0 ? v["price"] : tmp["price"] 
    
    new_price = Pinguu.price2string(parse(Float64, last_price) * (1 - config["extra_order_step"]), config["sell_precision"], round_up=true)
    quant = floor(config["order_volume"] * (config["extra_order_martingale"])^(extra_iteration + 1) / parse(Float64, new_price), digits=config["precision"])
    if extra_iteration < parse(Float64, config["extra_order_count"])
        open_orders["BUY"][new_id] = Dict()
        open_orders["BUY"][new_id]["origQty"] = quant
        open_orders["BUY"][new_id]["price"]   = new_price
        open_orders["BUY"][new_id]["status"]  = "place order"
        open_orders["BUY"][new_id]["time"]    = string(now())
        open(joinpath(bot_path, "open_orders.json"), "w") do f
            JSON.print(f, open_orders, 4)
        end
        open(joinpath(bot_path, "trigger.json"), "w") do f
            JSON.print(f, Dict(), 4)
        end
    end
    #
    ## Cancel current take profit orders
    if length(open_orders["SELL"]) > 0
        for (k2, v2) in open_orders["SELL"]
            if split(k2, "_")[end] == id_str
                tmp_sell = try client.get_order(
                    symbol=config["symbol"],
                    orderId=v2["orderId"])
                    catch 
                    try sleep(0.5)
                        client.get_order(
                            symbol=config["symbol"],
                            orderId=v2["orderId"])
                        catch nothing
                    end
                end
                if !(tmp_sell["status"] in [client.ORDER_STATUS_CANCELED, client.ORDER_STATUS_FILLED]) || tmp_sell == nothing
                    sleep(0.5)
                    tmp_sell = try client.cancel_order(
                        symbol=config["symbol"],
                        orderId=v2["orderId"])
                    catch
                        nothing
                    end
                end
                if tmp_sell !== nothing
                    if parse(Float64, v2["executedQty"]) > 0
                        random_id_str = "SELL-" * lpad(rand(1:1:10000), 5, "0")
                        while haskey(closed_orders[id_str], random_id_str)
                            random_id_str = "SELL-" * lpad(rand(1:1:10000), 5, "0")
                        end
                        closed_orders[id_str][random_id_str] = result
                        open(joinpath(bot_path, "closed_orders.json"), "w") do f
                            JSON.print(f, closed_orders, 4)
                        end
                    end
                    delete!(open_orders["SELL"], k2)
                else
                    #
                    ## Cancel failed
                    delete!(open_orders["SELL"], k2)
                    v2["status"] = "cancel order"
                    #
                    ## Give different ID to be able to create a new "main" order later
                    random_id_str = "SELL-" * lpad(rand(1:1:10000), 5, "0")
                    open_orders[random_id_str] = v2
                end
            end
        end
    end

    #
    ## Place command for take profit order
    open_orders["SELL"]["SELL_" * id_str] = Dict()
    open_orders["SELL"]["SELL_" * id_str]["status"] = "place order"
    open_orders["SELL"]["SELL_" * id_str]["id_str"] = id_str
    
    open(joinpath(bot_path, "open_orders.json"), "w") do f
        JSON.print(f, open_orders, 4)
    end
    open(joinpath(bot_path, "trigger.json"), "w") do f
        JSON.print(f, Dict(), 4)
    end

    #
    ## Create notification
    p = Dict()
    p["extra_iteration"] = extra_iteration
    p["executedQty"] = tmp["executedQty"]
    create_notification("buy exec", config, usr, params = p)
    if extra_iteration >= parse(Float64, config["extra_order_count"])
        create_notification("no volume", config, usr)
    end
end
export buy_executed

function cancel_buy(k, v, id_str, config, open_orders, closed_orders, bot_path, client)
    @info("Cancel Order")
    if haskey(v, "orderId")
        result = try client.cancel_order(
            symbol=config["symbol"],
            orderId=v["orderId"])
        catch
            nothing
        end
        if result !== nothing
            delete!(open_orders["BUY"], k)
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
            if parse(Float64, result["executedQty"]) > 0
                random_id_str = "EXTRA-" * lpad(rand(100:1:10000), 5, "0")
                while haskey(closed_orders[id_str], random_id_str)
                    random_id_str = "EXTRA-" * lpad(rand(100:1:10000), 5, "0")
                end
                closed_orders[id_str][random_id_str] = result
                open(joinpath(bot_path, "closed_orders.json"), "w") do f
                    JSON.print(f, closed_orders, 4)
                end
            end
        end
    else
        @info("Order has not been placed")
        #
        ## Order not placed, yet
        delete!(open_orders["BUY"], k)
        open(joinpath(bot_path, "open_orders.json"), "w") do f
            JSON.print(f, open_orders, 4)
        end   
        
    end
    open(joinpath(bot_path, "trigger.json"), "w") do f
        JSON.print(f, Dict(), 4)
    end
end
export cancel_buy


function buy_now(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees)
    extra_iteration = parse(Int64, split(split(k, "_")[1], "-")[2])
    if extra_iteration < parse(Float64, config["extra_order_count"])
        #
        # Cancel current BUY order
        if tmp["status"] != client.ORDER_STATUS_CANCELED
            result = try client.cancel_order(
                symbol=config["symbol"],
                orderId=v["orderId"])
            catch
                nothing
            end
            if result == nothing
                return nothing
            end
        else
            result = tmp
        end
        
        #
        # Check if that order was partially filled -> if so: move cancelled order to closed_orders
        if parse(Float64, result["executedQty"]) > 0
            result["time"] = string(now())
            !haskey(closed_orders, id_str) ? closed_orders[id_str] = Dict() : ""
            closed_orders[id_str][split(k, "_")[1]] = result
            extra_iteration += 1
            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                JSON.print(f, closed_orders, 4)
            end
        end
        #
        # Remove from open_orders
        delete!(open_orders["BUY"], k)
        #
        # Get new order details
        ticker = client.get_ticker(symbol=config["symbol"])["lastPrice"]
        quant = floor(parse(Float64, v["origQty"]), digits=config["precision"])
        new_id = "EXTRA-" * string(extra_iteration) * "_" * id_str
        #
        # Place new order
        order = try client.order_limit_buy(
            symbol=config["symbol"],
            quantity=quant,
            price=ticker)
        catch
            nothing
        end            

        if order !== nothing
            order["time"] = string(now())
#                 if parse(Float64, order["price"]) == 0
#                     order["price"] = Pinguu.price2string(parse(Float64, order["cummulativeQuoteQty"]) / parse(Float64, order["origQty"]), config["sell_precision"])
#                 end
            open_orders["BUY"][new_id] = order
        else
            open_orders["BUY"][new_id] = Dict()
            open_orders["BUY"][new_id]["origQty"] = quant
            open_orders["BUY"][new_id]["price"]   = ticker
            open_orders["BUY"][new_id]["status"]  = "place order"
            open_orders["BUY"][new_id]["time"]    = string(now())
        end
        open(joinpath(bot_path, "open_orders.json"), "w") do f
            JSON.print(f, open_orders, 4)
        end
    end
    open(joinpath(bot_path, "trigger.json"), "w") do f
        JSON.print(f, Dict(), 4)
    end
end
export buy_now




function partially_order(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees, minutes)
    if v["partial_time"] < string(now() - Minute(minutes))
        result = try client.cancel_order(
            symbol=config["symbol"],
            orderId=tmp["orderId"])
        catch
            nothing
        end
        if result !== nothing
            tmp["partial_time"] = v["partial_time"]
            v = deepcopy(tmp)
            v["status"] = "continue"
            open_orders["BUY"][k] = v
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
            p = Dict()
            p["extra_iteration"] = extra_iteration
            p["executedQty"] = tmp["executedQty"]
            create_notification("partial buy exec", config, usr, params = p)
        end
        if tmp["status"] == client.ORDER_STATUS_CANCELED
            v["status"] = "continue"
            open_orders["BUY"][k] = v
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
        end
    end
end
export partially_order

function first_order_takes_too_long(tmp, k, v, id_str, config, open_orders, closed_orders, bot_path, client, usr, fees, minutes)
    t = DateTime(split(id_str, "--")[end])
    if now() - t > Minute(minutes)
        result = try client.cancel_order(
            symbol=config["symbol"],
            orderId=v["orderId"])
        catch
            nothing
        end
        if result !== nothing
            delete!(open_orders["BUY"], k)
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
            Pinguu.create_notification("cycle closed", config, usr)
        end
    end
end
export first_order_takes_too_long

function add_fees_to_closed_order(order, config, bot_path, client)
    for t in order["trades"]
        sleep(0.5)
        commission = parse(Float64, t["commission"])
        commission_coin = parse(Float64, t["commission"])
        if commission != 0
            from = split(string(unix2datetime(t["time"]/1000)), ".")[1]
            to = split(string(unix2datetime(t["time"]/1000) + Minute(1)), ".")[1]
            #
            ## for commission
            if t["commissionAsset"] == config["farm_coin"]
                commission *= parse(Float64, t["price"])
            elseif t["commissionAsset"] != config["base_coin"]
                translator = string(t["commissionAsset"], config["base_coin"])
                klines = client.get_historical_klines(translator, client.KLINE_INTERVAL_1MINUTE, from, to)
                tt = Pinguu.klines2table(klines, time_warp=0)
                commission *= tt[1].close
                tmp_price_for_conversion = tt[1].close
            end
            #
            ## for commission_coin
            if t["commissionAsset"] != config["farm_coin"]
                translator = string(t["commissionAsset"], config["farm_coin"])
                # Translator exists
                klines = try client.get_historical_klines(translator, client.KLINE_INTERVAL_1MINUTE, from, to)
                    catch 
                    false
                end
                if klines == false
                    # Translator exists in other order
                    translator = string(config["farm_coin"], t["commissionAsset"])
                    klines = try client.get_historical_klines(translator, client.KLINE_INTERVAL_1MINUTE, from, to)
                        catch 
                        false
                    end
                else
                    tt = Pinguu.klines2table(klines, time_warp=0)
                    weightedAvgPrice = 1/tt[1].close
                end
                if klines == false
                    # Translator does not exist e.g. DOGEBNB
                    weightedAvgPrice = tmp_price_for_conversion / parse(Float64, t["price"])
                else
                    tt = Pinguu.klines2table(klines, time_warp=0)
                    weightedAvgPrice = 1/tt[1].close
                end

                if typeof(weightedAvgPrice) == String
                    weightedAvgPrice = parse(Float64, weightedAvgPrice)
                end
                commission_coin *= weightedAvgPrice
            end
            t["com"] = commission
            t["com_coin"] = commission_coin
        else
            t["com"] = 0
            t["com_coin"] = 0
        end
    end
    return order
end
export add_fees_to_closed_order

function check_ongoing_closed(id_str, config, closed_orders, bot_path, client)
    store = false
    for (id, order) in closed_orders[id_str]
        if !haskey(order, "trades")
            trades = client.get_my_trades(orderId=order["orderId"], symbol=order["symbol"])
            order["trades"] = trades
            order = try add_fees_to_closed_order(order, config, bot_path, client)
                catch 
                @info("Getting fees failed.")
                return
            end
            store = true
        end
    end
    if store
        open(joinpath(bot_path, "closed_orders.json"), "w") do f
            JSON.print(f, closed_orders, 4)
        end
    end
end
export check_ongoing_closed


