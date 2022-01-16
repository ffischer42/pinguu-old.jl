function freeze_order(config, trade_grid, check_key, client)
    if trade_grid[check_key]["side"] == client.SIDE_BUY
        Pinguu.freeze_buy_order(config, trade_grid, check_key, client)
    else
        Pinguu.freeze_sell_order(config, trade_grid, check_key, client)
    end
end
export freeze_order

function freeze_buy_order(config, trade_grid, check_key, client)
    price_str, info = string(check_key), trade_grid[check_key]
    test_bot = config["testing"] == "1" ? true : false
    if test_bot
        #
        ## Just overwrite it for test bots
        value = Pinguu.get_buy_value(config, trade_grid)
        qty = floor(value / parse(Float64, price_str), digits=config["precision"])
        grid_point = Dict(
            "price"  => price_str,
            "side"   => client.SIDE_BUY,
            "status" => "wait",
            "type"   => "normal",
            "qty"    => qty,
            "value"  => value
        )
        trade_grid[check_key] = grid_point
    else
        #
        ## Check order
        order = try client.get_order(symbol=info["order"]["symbol"], orderId=info["order"]["orderId"])
        catch
            return
        end

        if parse(Float64, order["executedQty"]) == 0
            #
            ## Cancel order
            if order["status"] != client.ORDER_STATUS_CANCELED
                result = try client.cancel_order(symbol=info["order"]["symbol"], orderId=info["order"]["orderId"])
                catch
                    return
                end
            end
            value = Pinguu.get_buy_value(config, trade_grid)
            qty = floor(value / parse(Float64, price_str), digits=config["precision"])
            grid_point = Dict(
                "price"  => price_str,
                "side"   => client.SIDE_BUY,
                "status" => "wait",
                "type"   => "normal",
                "qty"    => qty,
                "value"  => value
            )
            trade_grid[check_key] = grid_point
        else
            trade_grid[check_key]["status"] = "frozen"
        end
        open(joinpath(config["bot_path"], "trade_grid.json"), "w") do f
            JSON.print(f, trade_grid, 4)
        end
    end
end
export freeze_buy_order

function freeze_sell_order(config, trade_grid, check_key, client)
    trade_grid[check_key]["status"] = "frozen"
    open(joinpath(config["bot_path"], "trade_grid.json"), "w") do f
        JSON.print(f, trade_grid, 4)
    end
end
export freeze_sell_order


function cancel_frozen_buy(config, trade_grid, check_key, client)
    price_str, info = string(check_key), trade_grid[check_key]
    test_bot = config["testing"] == "1" ? true : false
    if test_bot
        #
        ## Just overwrite it for test bots
        value = Pinguu.get_buy_value(config, trade_grid)
        qty = floor(value / parse(Float64, price_str), digits=config["precision"])
        grid_point = Dict(
            "price"  => price_str,
            "side"   => client.SIDE_BUY,
            "status" => "wait",
            "type"   => "normal",
            "qty"    => qty,
            "value"  => value
        )
        trade_grid[check_key] = grid_point
        open(joinpath(config["bot_path"], "trade_grid.json"), "w") do f
            JSON.print(f, trade_grid, 4)
        end
    else
        if parse(Float64, info["order"]["executedQty"]) == 0
            #
            ## Check order
            order = try client.get_order(symbol=info["order"]["symbol"], orderId=info["order"]["orderId"])
            catch
                return
            end

            if parse(Float64, order["executedQty"]) == 0
                #
                ## Cancel order
                if order["status"] != client.ORDER_STATUS_CANCELED
                    result = try client.cancel_order(symbol=info["order"]["symbol"], orderId=info["order"]["orderId"])
                    catch
                        return
                    end
                end
                value = Pinguu.get_buy_value(config, trade_grid)
                qty = floor(value / parse(Float64, price_str), digits=config["precision"])
                grid_point = Dict(
                    "price"  => price_str,
                    "side"   => client.SIDE_BUY,
                    "status" => "wait",
                    "type"   => "normal",
                    "qty"    => qty,
                    "value"  => value
                )
                trade_grid[check_key] = grid_point
                open(joinpath(config["bot_path"], "trade_grid.json"), "w") do f
                    JSON.print(f, trade_grid, 4)
                end
            else
                @info("Partially executed")
            end
        end
    end
end
export cancel_frozen_buy