function check_grid_buy!(config, trade_grid, price_str, client, bot_path)
    #
    ## Test Bot?
    test_bot = config["testing"] == "1" ? true : false
    info = trade_grid[price_str]
    
    #
    ##
    if test_bot 
        ticker, current_price = Pinguu.get_current_ticker(client, config, use_api=false)
        if current_price <= parse(Float64, info["order"]["price"])
            tmp = Dict(
                "status" => client.ORDER_STATUS_FILLED,
                "price" => info["order"]["price"],
                "time" => string(now()),
                "timeInForce" => client.TIME_IN_FORCE_GTC,
                "orderId" => 42,
                "executedQty" => info["order"]["origQty"],
                "clientOrderId" =>"2Y5skq9An12HbHQUDkFA9T",
                "symbol" => config["symbol"],
                "cummulativeQuoteQty" => round(parse(Float64, info["order"]["price"])*info["order"]["origQty"], digits=config["sell_precision"]),
                "origQty" =>info["order"]["origQty"],
                "side" =>client.SIDE_BUY,
                "type" =>"LIMIT",
                "test" => "true",
            )
        else
            tmp = Dict(
                "status" => client.ORDER_STATUS_NEW,
                "price" => info["order"]["price"],
                "time" => string(now()),
                "timeInForce" => client.TIME_IN_FORCE_GTC,
                "orderId" => 42,
                "executedQty" => "0.00",
                "clientOrderId" =>"2Y5skq9An12HbHQUDkFA9T",
                "symbol" => config["symbol"],
                "cummulativeQuoteQty" => "0.00",
                "origQty" =>info["order"]["origQty"],
                "side" =>client.SIDE_BUY,
                "type" =>"LIMIT",
                "test" => "true"
            )
        end
    else
        tmp = try client.get_order(
                symbol=config["symbol"],
                orderId=info["order"]["orderId"]
            )
        catch 
            return
        end
    end
    ##
    #


    #
    ## Store changes
    if tmp["status"] != info["order"]["status"]
        trade_grid[price_str]["order"] = tmp
        open(joinpath(bot_path, "trade_grid.json"), "w") do f
            JSON.print(f, trade_grid, 4)
        end
    end


    #
    ## Order filled
    if tmp["status"] == client.ORDER_STATUS_FILLED
        next_gridpoints = Pinguu.get_next_gridpoints(trade_grid, price_str)
        new_sell_price = next_gridpoints["SELL"]
        new_sell = Dict(
            "status" => "place",
            "side" => client.SIDE_SELL,
            "type" => "normal",
            "price" => new_sell_price, 
            "qty" => tmp["executedQty"],
            "buy_order" => tmp,
        )
        if haskey(info, "current_volume")
            new_sell["current_volume"] = info["current_volume"]
        end
            
        new_current = Dict("status" => "current")
        
        #
        ## Place new SELL and CURRENT
        trade_grid[new_sell_price] = new_sell
        trade_grid[price_str] = new_current
        
        #
        ## Freeze all ongoing orders
        for (k,v) in trade_grid
            if v["status"] == "check"
                trade_grid[k]["status"] = "freeze"
            end
        end
        
        #
        ## Create next BUY
        if haskey(next_gridpoints, "BUY")
            next_buy_price = next_gridpoints["BUY"]
            if trade_grid[next_buy_price]["status"] == "wait"
                trade_grid[next_buy_price]["status"] = "place"
            elseif trade_grid[next_buy_price]["status"] in ["frozen", "freeze"]
                trade_grid[next_buy_price]["status"] = "defrost"
            end
        end
        #
        ## Update grid file
        open(joinpath(bot_path, "trade_grid.json"), "w") do f
            JSON.print(f, trade_grid, 4)
        end
    end
end
export check_grid_buy!