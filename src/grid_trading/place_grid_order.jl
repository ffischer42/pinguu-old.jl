function place_grid_order!(config, trade_grid, price_str, client, bot_path)
    #
    ## Test Bot?
    test_bot = config["testing"] == "1" ? true : false
    
    info = trade_grid[price_str]
    
    if info["side"] == client.SIDE_BUY
        #
        ## Calculate BUY qty depending on thes. volume
        qty = Pinguu.get_buy_value(config, trade_grid) / parse(Float64, price_str)
        qty = floor(qty, digits=config["precision"])
    else
        #
        ## Get SELL qty
        qty = typeof(info["qty"]) != Float64 ? parse(Float64, info["qty"]) : info["qty"]
    end
    tmp = Dict(
        "status" => "check", 
        "side" => info["side"],
        "price" => price_str, 
        "type" => info["type"],
        "qty" => qty
    )
    
    current_volume = Pinguu.get_current_volume(config)
    
    if info["side"] == client.SIDE_BUY
        tmp["current_volume"] = current_volume
    end
    #
    ## Sell of extra coin volume, take buy_order 
    if info["type"] == "normal" && info["side"] == client.SIDE_SELL
        tmp["buy_order"] = info["buy_order"]
        if haskey(info, "current_volume")
            tmp["current_volume"] = info["current_volume"]
        else
            tmp["current_volume"] = current_volume
        end
    end
    
    
    if test_bot
        #
        ## PLACE BUY TESTING
        order = try client.create_test_order(
                symbol=config["symbol"],
                side=info["side"],
                type=client.ORDER_TYPE_LIMIT,
                timeInForce=client.TIME_IN_FORCE_GTC,
                quantity=tmp["qty"],
                price=tmp["price"]
            )
            catch
            return
        end
        tmp["order"] = Dict(
            "price" => price_str,
            "orderId" => 42,
            "executedQty" => "0.00",
            "origQty" => tmp["qty"],
            "side" => tmp["side"],
            "type" => "limit",
            "symbol" => config["symbol"],
            "status" => "NEW",
            "cummulativeQuoteQty" => "0.00000000",
            "executedQty" => "0.00",
            "time" => string(now())
        )
        ##
        #
    else
        #
        ## PLACE ORDER
        if tmp["side"] == client.SIDE_BUY
            order = try client.order_limit_buy(
                    symbol=config["symbol"],
                    quantity=tmp["qty"],
                    price=tmp["price"]
                );
            catch
                return
            end
        else
            order = try client.order_limit_sell(
                    symbol=config["symbol"],
                    quantity=tmp["qty"],
                    price=tmp["price"]
                );
            catch
                return
            end
        end
        tmp["order"] = order
        tmp["order"]["time"] = string(now())
        ##
        #
    end

    trade_grid[price_str] = tmp
    open(joinpath(bot_path, "trade_grid.json"), "w") do f
        JSON.print(f, trade_grid, 4)
    end
end
export place_grid_order!