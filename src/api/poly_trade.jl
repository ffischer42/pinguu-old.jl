
#
#
# REAL MONEY ######################################################
# REAL MONEY ######################################################
#
#

function place_first_poly_order!(config, open_orders, bot_path, client, usr)
    @info("NEW order found!")
    for (k,v) in open_orders["NEW"]
        ticker = client.get_ticker(symbol=k)["lastPrice"]
        current = parse(Float64, ticker)
        
        id_str = v["trigger"] * "--" * string(now())
        symbol = k
        quant = floor(config["order_volume"] / current, digits=config["symbols"][symbol]["precision"])
        order = try client.order_limit_buy(
            symbol=symbol,
            quantity=quant,
            price=ticker);
        catch
            nothing
        end
        if order !== nothing
            open_orders["BUY"]["EXTRA-0_" * id_str] = order
            delete!(open_orders["NEW"], k)
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
            p = Dict()
            p["ticker"] = ticker
            try create_notification("new cycle", config, usr, params = p)
                catch;
            end
        end
    end
    return open_orders
end


function check_open_poly_sell!(config, open_orders, closed_orders, bot_path, client, usr)
    for (k,v) in open_orders["SELL"]
        if length(open_orders["SELL"]) > 0
            fees = client.get_trade_fee(symbol=v["symbol"])["tradeFee"][1]
        end
        if v["status"] != "place order"
            skip = false
            tmp = try client.get_order(
                symbol=v["symbol"],
                orderId=v["orderId"])
                catch 
                @info("Skipped..")
                sleep(0.25)
                skip = true
            end
            if !skip
                id_str = split(k, "_")[end]
                #
                # IS SELL CORRECT??
                #
                if tmp["status"] != "FILLED"
                    qty_new = 0
                    value   = 0
                    for (k2,v2) in closed_orders[id_str]
                        if v2["side"] == "BUY"
                            qty_new += parse(Float64, v2["executedQty"])
                            value += parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 + fees["taker"]) 
                        else
                            qty_new -= parse(Float64, v2["executedQty"])
                            value -= parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 - fees["maker"]) 
                        end
                    end
                    new_quant = floor(qty_new, digits=v["precision"])
                    new_price = string(floor(value / new_quant * (1 + parse(Float64, config["take_profit"])/100), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                    if new_quant > parse(Float64, v["origQty"]) * 1.02
                        @info("SELL PLACED WITH WRONG QTY!")
                        result = try client.cancel_order(
                            symbol=v["symbol"],
                            orderId=v["orderId"])
                        catch
                            nothing
                        end
                        new_id    = "SELL_" * id_str 
                        order = try client.order_limit_sell(
                            symbol=v["symbol"],
                            quantity=new_quant,
                            price=new_price);
                            catch 
                            nothing
                        end
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
                            open_orders["SELL"][new_id]["symbol"]  = v["symbol"]
                            open_orders["SELL"][new_id]["if_fail"] = new_quant - 1/10^config["symbols"][v["symbol"]]["precision"]           

                            open(joinpath(bot_path, "open_orders.json"), "w") do f
                                JSON.print(f, open_orders, 4)
                            end
                        end
                    end
                end
                #
                #
                #
                
                if tmp["status"] == "FILLED"
                    !(id_str in keys(closed_orders)) ? closed_orders[id_str] = Dict() : ""
                    tmp["time"] = string(now())
                    
                    delete!(open_orders["SELL"], k)
                    for (k2, v2) in open_orders["BUY"]
                        if split(k2, "_")[end] == id_str && v2["symbol"] == v["symbol"]
                            sleep(0.2)
                            tmp_buy = try client.get_order(
                                symbol=v["symbol"],
                                orderId=v2["orderId"])
                            catch 
                                nothing
                            end
                            
                            if tmp_buy !== nothing
                                if !(tmp_buy["status"] in ["FILLED", "CANCELED"])
                                    sleep(0.2)
                                    result = try client.cancel_order(
                                        symbol=v["symbol"],
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
                        if abs(val) > config["symbols"][v["symbol"]]["min_qty"]
                            #
                            ## qty is high enough to be sold
                            new_qty = floor(net_qty, digits=config["symbols"][v["symbol"]]["precision"])
                            new_price = string(floor(abs(val)/net_qty * (1 + parse(Float64, config["take_profit"])/100), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                            sleep(0.2)
                            order = try client.order_limit_sell(
                                symbol=v["symbol"],
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
                                    new_price = string(round(parse(Float64, new_price) * (1 - config["extra_order_step"]), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                                    quant = floor(config["order_volume"] * (config["extra_order_martingale"])^(extra_iteration + 1) / parse(Float64, new_price), digits=config["symbols"][v["symbol"]]["precision"])

                                    new_buy = Dict()
                                    new_buy["status"] = "place order"
                                    new_buy["origQty"] = quant
                                    new_buy["price"] = new_price
                                    new_buy["symbol"] = v["symbol"]
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
                                open_orders["SELL"][new_id]["symbol"]  = v["symbol"]
                                open_orders["SELL"][new_id]["fail"]    = 0
                                open_orders["SELL"][new_id]["if_fail"] = new_quant - 1/10^config["symbols"][v["symbol"]]["precision"]           

                                open(joinpath(bot_path, "open_orders.json"), "w") do f
                                    JSON.print(f, open_orders, 4)
                                end
                            end
                        else
                            #
                            ## qty is NOT high enough to be sold
                            new_price = string(floor(abs(val)/net_qty * (1 + parse(Float64, config["take_profit"])/100), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                            
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
                                new_price = string(round(parse(Float64, new_price) * (1 - config["extra_order_step"]), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                                quant = floor(config["order_volume"] * (config["extra_order_martingale"])^(extra_iteration + 1) / parse(Float64, new_price), digits=config["symbols"][v["symbol"]]["precision"])

                                new_buy = Dict()
                                new_buy["status"]  = "place order"
                                new_buy["origQty"] = quant
                                new_buy["price"]   = new_price
                                new_buy["symbol"]  = v["symbol"]
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
                elseif tmp["status"] == "CANCELED"
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
            if v["fail"] == 0
                qty = floor(v["origQty"], digits=config["symbols"][v["symbol"]]["precision"])
            elseif v["fail"] == 1
                
                id_str = split(k, "_")[end]
                #
                # IS SELL CORRECT??
                #
                qty_new = 0
                value   = 0
                for (k2,v2) in closed_orders[id_str]
                    if v2["side"] == "BUY"
                        qty_new += parse(Float64, v2["executedQty"])
                        value += parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 + fees["taker"]) 
                    else
                        qty_new -= parse(Float64, v2["executedQty"])
                        value -= parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 - fees["maker"]) 
                    end
                end
                new_quant = floor(qty_new, digits=config["symbols"][v["symbol"]]["precision"])
                new_price = string(floor(value / new_quant * (1 + parse(Float64, config["take_profit"])/100), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                result = try client.cancel_order(
                    symbol=v["symbol"],
                    orderId=v["orderId"])
                catch
                    nothing
                end
                qty = new_quant
            else
                account = client.get_account()["balances"];
                new = new_quant
                for bal in account
                    if bal["asset"] == v["symbol"][1:3]
                        if parse(Float64, bal["free"]) <= new_quant
                            new = parse(Float64, bal["free"])
                        end
                    end
                end
                qty = floor(new, digits=config["symbols"][v["symbol"]]["precision"])
            end
            order = try client.order_limit_sell(
                symbol=v["symbol"],
                quantity=qty,
                price=v["price"]);
                catch 
                nothing
            end
            if order !== nothing
                order["time"] = string(now())
                open_orders["SELL"][k] = order
                open(joinpath(bot_path, "open_orders.json"), "w") do f
                    JSON.print(f, open_orders, 4)
                end
            else
                v["fail"] = 1
                open(joinpath(bot_path, "open_orders.json"), "w") do f
                    JSON.print(f, open_orders, 4)
                end
            end
        end
    end
    sleep(0.25)
    return open_orders, closed_orders
end


function check_open_poly_buy!(config, open_orders, closed_orders, bot_path, client, usr)
    for (k,v) in open_orders["BUY"]
        if v["status"] == "place order"
            quant = round(v["origQty"], digits=config["symbols"][v["symbol"]]["precision"])
            new_price = v["price"]
            new_id = k
            order = try client.order_limit_buy(
                symbol= v["symbol"],
                quantity=quant,
                price=new_price);
                catch 
                nothing
            end
            if order !== nothing
                order["time"] = string(now())
                open_orders["BUY"][new_id] = order
            else
                open_orders["BUY"][new_id] = Dict()
                open_orders["BUY"][new_id]["origQty"] = quant
                open_orders["BUY"][new_id]["price"]   = new_price
                open_orders["BUY"][new_id]["symbol"]  = v["symbol"]
                open_orders["BUY"][new_id]["status"]  = "place order"
                open_orders["BUY"][new_id]["time"]    = string(now())
            end
            open(joinpath(bot_path, "open_orders.json"), "w") do f
                JSON.print(f, open_orders, 4)
            end
        else
            skip = false
            tmp = try client.get_order(
                symbol=v["symbol"],
                orderId=v["orderId"])
                catch 
                @info("Skipped..")
                sleep(0.25)
                skip = true
            end
            if !skip
                if tmp["status"] == "FILLED" || v["status"] == "continue" || parse(Float64, tmp["executedQty"]) == parse(Float64, tmp["origQty"])
                    if tmp["status"] != "FILLED" && tmp["status"] != "CANCELLED"
                        result = try client.cancel_order(
                            symbol=v["symbol"],
                            orderId=tmp["orderId"])
                        catch
                            nothing
                        end
                    end

                    fees = client.get_trade_fee(symbol=v["symbol"])["tradeFee"][1]
                    id_str = split(k, "_")[end]
                    extra_iteration = parse(Int64, split(split(k, "_")[1], "-")[2])
                    !(id_str in keys(closed_orders)) ? closed_orders[id_str] = Dict() : ""
                    tmp["time"] = string(now())
                    closed_orders[id_str][split(k, "_")[1]] = deepcopy(tmp);
                    open(joinpath(bot_path, "closed_orders.json"), "w") do f
                        JSON.print(f, closed_orders, 4)
                    end

                    delete!(open_orders["BUY"], k)
                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                        JSON.print(f, open_orders, 4)
                    end

                    #
                    # EXTRA BUY
                    #
                    new_id = "EXTRA-" * string(extra_iteration + 1) * "_" * id_str
                    new_price = string(round(parse(Float64, v["price"]) * (1 - config["extra_order_step"]), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                    quant = floor(config["order_volume"] * (config["extra_order_martingale"])^(extra_iteration + 1) / parse(Float64, new_price), digits=config["symbols"][v["symbol"]]["precision"])
                    if extra_iteration < parse(Float64, config["extra_order_count"])
                        order = try client.order_limit_buy(
                            symbol= v["symbol"],
                            quantity=quant,
                            price=new_price);
                            catch 
                            nothing
                        end
                        if order !== nothing
                            order["time"] = string(now())
                            open_orders["BUY"][new_id] = order
                        else
                            open_orders["BUY"][new_id] = Dict()
                            open_orders["BUY"][new_id]["origQty"] = quant
                            open_orders["BUY"][new_id]["price"]   = new_price
                            open_orders["BUY"][new_id]["status"]  = "place order"
                            open_orders["BUY"][new_id]["symbol"]  = v["symbol"]
                            open_orders["BUY"][new_id]["time"]    = string(now())
                        end
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end
                    end
                    #
                    # TAKE PROFIT
                    #
                    # Cancel current take profit orders
                    if length(open_orders["SELL"]) > 0
                        for (k2, v2) in open_orders["SELL"]
                            if split(k2, "_")[end] == id_str && v["symbol"] == v2["symbol"]
                                tmp_sell = try client.get_order(
                                    symbol=v["symbol"],
                                    orderId=v2["orderId"])
                                    catch 
                                    try sleep(0.2)
                                        client.get_order(
                                            symbol=v["symbol"],
                                            orderId=v2["orderId"])
                                        catch nothing
                                    end
                                end
                                if !(tmp_sell["status"] in ["CANCELED", "FILLED"]) || tmp_sell == nothing
                                    sleep(0.1)
                                    tmp_sell = try client.cancel_order(
                                        symbol=v["symbol"],
                                        orderId=v2["orderId"])
                                    catch
                                        nothing
                                    end
                                end
                                if tmp_sell !== nothing
                                    if parse(Float64, v2["executedQty"]) > 0
                                        closed_orders[id_str]["SELL-" * lpad(rand(1:1:10000), 5, "0")] = result
                                        open(joinpath(bot_path, "closed_orders.json"), "w") do f
                                            JSON.print(f, closed_orders, 4)
                                        end
                                    end
                                    delete!(open_orders["SELL"], k2)
                                end
                            end
                        end
                    end

                    qty_new = 0
                    value   = 0
                    for (k2,v2) in closed_orders[id_str]
                        if v2["side"] == "BUY"
                            qty_new += parse(Float64, v2["executedQty"])
                            value += parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 + fees["taker"])
                        else
                            qty_new -= parse(Float64, v2["executedQty"])
                            value -= parse(Float64, v2["cummulativeQuoteQty"]) * (1.0 - fees["maker"]) 
                        end
                    end
                    new_id    = "SELL_" * id_str 
                    new_quant = floor(qty_new, digits=config["symbols"][v["symbol"]]["precision"])
                    new_price = string(floor(value / new_quant * (1 + fees["maker"] + parse(Float64, config["take_profit"])/100), digits=config["symbols"][v["symbol"]]["sell_precision"]))
                    if value > config["symbols"][v["symbol"]]["min_qty"]
                        order = try client.order_limit_sell(
                            symbol=v["symbol"],
                            quantity=new_quant,
                            price=new_price);
                            catch 
                            nothing
                        end
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
                            open_orders["SELL"][new_id]["symbol"]  = v["symbol"]
                            open_orders["SELL"][new_id]["if_fail"] = new_quant - 1/10^config["symbols"][v["symbol"]]["precision"]           

                            open(joinpath(bot_path, "open_orders.json"), "w") do f
                                JSON.print(f, open_orders, 4)
                            end
                        end
                    end
                    p = Dict()
                    p["extra_iteration"] = extra_iteration
                    p["executedQty"] = tmp["executedQty"]
                    try create_notification("buy exec", config, usr, params = p)
                        catch;
                    end
                    if !(extra_iteration < parse(Float64, config["extra_order_count"]))
                        try create_notification("no volume", config, usr)
                            catch;
                        end
                    end
                elseif v["status"]  == "cancel"
                    result = try client.cancel_order(
                        symbol=v["symbol"],
                        orderId=v["orderId"])
                    catch
                        nothing
                    end
                    if result !== nothing
                        delete!(open_orders["BUY"], k)
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end                    
                    end
                elseif v["status"]  == "buy now"
                    @info(v["status"])
                    id_str = split(k, "_")[end]
                    extra_iteration = parse(Int64, split(split(k, "_")[1], "-")[2])
                    if extra_iteration < parse(Float64, config["extra_order_count"])
                        #
                        # Cancel current BUY order
                        if tmp["status"] != "CANCELED"
                            result = try client.cancel_order(
                                symbol=v["symbol"],
                                orderId=v["orderId"])
                            catch
                                nothing
                            end
                        else
                            result = tmp
                        end
#                         @info(result)
                        if result !== nothing
                            @info("order cancelled")
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
                            ticker = client.get_ticker(symbol=v["symbol"])["lastPrice"]
                            quant = floor(parse(Float64, v["origQty"]), digits=config["symbols"][v["symbol"]]["precision"])
                            new_id = "EXTRA-" * string(extra_iteration) * "_" * id_str
                            #
                            # Place new order
                            order = try client.order_limit_buy(
                                symbol=v["symbol"],
                                quantity=quant,
                                price=ticker);
                                catch 
                                nothing
                            end
                            if order !== nothing
                                order["time"] = string(now())
                                open_orders["BUY"][new_id] = order
                            else
                                open_orders["BUY"][new_id] = Dict()
                                open_orders["BUY"][new_id]["origQty"] = quant
                                open_orders["BUY"][new_id]["price"]   = ticker
                                open_orders["BUY"][new_id]["status"]  = "place order"
                                open_orders["BUY"][new_id]["symbol"]  = v["symbol"]
                                open_orders["BUY"][new_id]["time"]    = string(now())
                            end
                            open(joinpath(bot_path, "open_orders.json"), "w") do f
                                JSON.print(f, open_orders, 4)
                            end
                        end
                    else
                        open_orders["BUY"][k] = tmp
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end
                    end
                elseif tmp["status"] == "CANCELED" && parse(Float64, tmp["executedQty"]) == 0
                    delete!(open_orders["BUY"], k)
                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                elseif tmp["status"] == "PARTIALLY_FILLED" && v["status"] != tmp["status"]
                    v = deepcopy(tmp)
                    v["time"] = string(now())
                    v["partial_time"] = string(now())
                    open_orders["BUY"][k] = v
                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                elseif parse(Float64, tmp["executedQty"]) != 0 && parse(Float64, tmp["executedQty"]) != parse(Float64, tmp["origQty"]) && haskey(v, "partial_time")
                    if v["partial_time"] < string(now() - Minute(2))
                        result = try client.cancel_order(
                            symbol=v["symbol"],
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
                            try create_notification("partial buy exec", config, usr, params = p)
                                catch;
                            end
                        end
                        if tmp["status"] == "CANCELED"
                            v["status"] = "continue"
                            open_orders["BUY"][k] = v
                            open(joinpath(bot_path, "open_orders.json"), "w") do f
                                JSON.print(f, open_orders, 4)
                            end
                        end
                    end
                elseif tmp["status"] != v["status"]
                    tmp["time"] = string(now())
                    open_orders["BUY"][k] = tmp
                    if haskey(v, "partial_time")
                        open_orders["BUY"][k]["partial_time"] = v["partial_time"]
                    end
                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                elseif tmp["status"] == "NEW" && split(k, "_")[1] == "EXTRA-0" && parse(Float64, tmp["executedQty"]) == 0.0
                    # Maybe the first BUY has to be updated
                    id_str = split(k, "_")[end]
                    t = DateTime(split(id_str, "--")[end])
                    if now() - t > Minute(1)
                        result = try client.cancel_order(
                            symbol=v["symbol"],
                            orderId=v["orderId"])
                        catch
                            nothing
                        end
                        if result !== nothing
                            delete!(open_orders["BUY"], k)
                            open(joinpath(bot_path, "open_orders.json"), "w") do f
                                JSON.print(f, open_orders, 4)
                            end
                            try create_notification("cycle closed", config, usr)
                                catch;
                            end
                        end
                    end
                end
            end
        end
    end
    return open_orders, closed_orders
end
