function finish_grid_bot(client, config, bot_path)
    trade_grid = JSON.parsefile(joinpath(bot_path, "trade_grid.json"));

    #
    ## Cancel all orders
    all_canceled = true
    for (price, v) in trade_grid
        if haskey(v, "order")
            order = v["order"]
            if !(order["status"] in [client.ORDER_STATUS_FILLED, client.ORDER_STATUS_CANCELED, client.ORDER_STATUS_EXPIRED])
                sleep(0.5)
                result = try client.get_order(symbol=order["symbol"], orderId=order["orderId"])
                    catch 
                    nothing
                end
                if result !== nothing
                    sleep(0.5)
                    if !(result["status"] in [client.ORDER_STATUS_FILLED, client.ORDER_STATUS_CANCELED, client.ORDER_STATUS_EXPIRED])
                        result = try client.cancel_order(symbol=order["symbol"], orderId=order["orderId"])
                            catch 
                            nothing
                        end
                    end
                else
                    all_canceled = false
                    continue
                end
                if result !== nothing
                    trade_grid[price]["order"] = result
                else 
                    all_canceled = false
                    continue
                end
            end
        end
    end
    open(joinpath(bot_path, "trade_grid.json"), "w") do f
        JSON.print(f, trade_grid, 4)
    end
    if all_canceled == false
        return
    end
    trade_grid = JSON.parsefile(joinpath(bot_path, "trade_grid.json"));
    leftover_bought = 0
    for (k,v) in trade_grid
        if haskey(v, "order")
            leftover_bought += typeof(v["order"]["executedQty"]) == Float64 ? v["order"]["executedQty"] : parse(Float64, v["order"]["executedQty"])
        end
    end
    if leftover_bought == 0
        config["status"] = "finished"
    else
        config["status"] = "leftover"
    end
    open(joinpath(bot_path, "config.json"), "w") do f
        JSON.print(f, config, 4)
    end
end
export finish_grid_bot