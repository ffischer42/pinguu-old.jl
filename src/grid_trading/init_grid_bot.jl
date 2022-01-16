function init_grid_bot(client, config, bot_path)
    @info(now())
    @info(config["name"])
    @info("Preparation")
    @info("-------------")
    
    #
    # Add min_qty, precision, sell_precision, min_step, tick_size
    if !haskey(config, "precision") || !haskey(config, "sell_precision")
        @info("Adding precisions")
        buy_precision, sell_precision, min_qty, min_step, tickSize = Pinguu.get_precision(client, config["symbol"])
        config["precision"] = buy_precision
        config["sell_precision"] = sell_precision
        config["min_qty"] = min_qty
        config["min_step"] = min_step
        config["tick_size"] = tickSize
        open(joinpath(bot_path, "config.json"), "w") do f
            JSON.print(f, config, 4)
        end
    end

    
    #
    ## Place initial order
    if config["init_state"]["status"] == "not placed"
        @info("Placing initial order")
        order = try Pinguu.place_init_grid_order(client, config)
            catch 
            nothing
        end
        if order !== nothing
            config["init_state"]["status"] = "placed"
            config["init_state"]["order"] = order
            open(joinpath(bot_path, "config.json"), "w") do f
                JSON.print(f, config, 4)
            end
        end
        return
    end
    
    #
    ## Check initial order. Change to "FILLED" if order has been fileed
    if config["init_state"]["status"] == "placed"
        @info("Checking initial order")
        tmp = try Pinguu.check_init_grid_order(client, config)
            catch
            nothing
        end
        @info(tmp["status"])
        if tmp !== nothing
            if tmp["status"] == client.ORDER_STATUS_FILLED
                config["init_state"]["status"] = client.ORDER_STATUS_FILLED
                config["init_state"]["order"] = [tmp]                 
                open(joinpath(bot_path, "config.json"), "w") do f
                    JSON.print(f, config, 4)
                end
            end
        end
        return
    end
    
    #
    ## Calculate average price, if several orders have been executed
    if config["init_state"]["status"] == client.ORDER_STATUS_FILLED
        @info("Evaluating filled initial order")
        vals = []
        prices = []
        executedQty = []
        for order in config["init_state"]["order"]
            cQty   = typeof(order["cummulativeQuoteQty"]) != Float64 ? parse(Float64, order["cummulativeQuoteQty"]) : order["cummulativeQuoteQty"]
            oPrice = typeof(order["price"]) != Float64 ? parse(Float64, order["price"]) : order["price"]
            exQty  = typeof(order["executedQty"]) != Float64 ? parse(Float64, order["executedQty"]) : order["executedQty"]
            push!(vals, cQty)
            push!(prices, oPrice)
            push!(executedQty, exQty)
        end
        avg_price = sum(vals) / sum(vals ./ prices)
        avg_price = Pinguu.price2string(avg_price, config["sell_precision"])
        config["init_state"]["price"] = avg_price
        config["init_state"]["cummulativeQuoteQty"] = sum(vals) * (1-0.00075) # Estimate Fees
        config["init_state"]["executedQty"] = sum(executedQty)
        config["init_state"]["status"] = "order completed"
        
        
        #
        ## Add fees of inital orders
        i = 1
        for i in eachindex(config["init_state"]["order"])
            order = config["init_state"]["order"][i]
            if !haskey(order, "trades")
                trades = client.get_my_trades(symbol=config["symbol"], orderId=order["orderId"])
                config["init_state"]["order"][i]["trades"] = trades
                open(joinpath(bot_path, "config.json"), "w") do f
                    JSON.print(f, config, 4)
                end
            end
            if !haskey(order, "fee")
                order["fee"] = calc_order_fee(client, order["trades"], config)
                open(joinpath(bot_path, "config.json"), "w") do f
                    JSON.print(f, config, 4)
                end
            end
        end
        if !haskey(config["init_state"], "fee")
            fee = 0
            for order in config["init_state"]["order"]
                fee += order["fee"]
            end
            config["init_state"]["fee"] = fee
        end
        config["init_state"]["sold"] = 0 
        open(joinpath(bot_path, "config.json"), "w") do f
            JSON.print(f, config, 4)
        end
        return
    end

    #
    ## Create folders
    !isdir(joinpath(bot_path, "closed_orders")) ? mkpath(joinpath(bot_path, "closed_orders")) : "dir exists"
    !isdir(joinpath(bot_path, "closed_init_orders")) ? mkpath(joinpath(bot_path, "closed_init_orders")) : "dir exists"
    !isdir(joinpath(bot_path, "history")) ? mkpath(joinpath(bot_path, "history")) : "dir exists"
    !isdir(joinpath(bot_path, "temp")) ? mkpath(joinpath(bot_path, "temp")) : "dir exists"

    #
    ## Create Grid
    if !isfile(joinpath(bot_path, "trade_grid.json"))
        trade_grid = try Pinguu.create_trade_grid(client, config, bot_path)
        catch
            @info("Trade grid creation failed")
            return 
        end
        open(joinpath(bot_path, "trade_grid.json"), "w") do f
            JSON.print(f, trade_grid, 4)
        end
        return
    end
    
    #
    ## Start trading! :-9
    config["status"]       = "active"
    config["start"]        = string(now())
    config["thes_factor"]  = 1.0
    config["thes_volume"]  = 0.0
    config["extra_volume"] = Dict()
    config["bot_path"]     = bot_path
    open(joinpath(bot_path, "config.json"), "w") do f
        JSON.print(f, config, 4)
    end
end
export init_grid_bot