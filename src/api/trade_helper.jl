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
        if order["side"] == "SELL"
            closed_orders[id_str]["SELL-" * lpad(rand(1:1:100000), 6, "0")] = deepcopy(result);
        else
            closed_orders[id_str]["EXTRA-" * lpad(rand(100:1:100000), 6, "0")] = deepcopy(result);
        end
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

function check_stopped_orders(k, v, config, open_orders, closed_orders, bot_path, client, usr)
    @info("Stopping order")
    order = Pinguu.stop_order(v, k, config, closed_orders, bot_path, client)
    open(joinpath(bot_path, "trigger.json"), "w") do f
        JSON.print(f, Dict(), 4)
    end
    if order !== nothing
        #
        ## Change v with temp order
        open_orders[order["side"]][k] = order
        open(joinpath(bot_path, "open_orders.json"), "w") do f
            JSON.print(f, open_orders, 4)
        end
        return 
    end
    @info("Cancelling order failed. Will try again soon.")
end
export check_stopped_orders


function check_orders_to_revive(k, v, config, open_orders, closed_orders, bot_path, client, usr)
    order = Pinguu.revive_order(v, k, config, closed_orders, bot_path, client)
    open(joinpath(bot_path, "trigger.json"), "w") do f
        JSON.print(f, Dict(), 4)
    end                
    if order !== nothing
        #
        ## Change v with temp order
        open_orders[order["side"]][k] = order
        open(joinpath(bot_path, "open_orders.json"), "w") do f
            JSON.print(f, open_orders, 4)
        end
        v = deepcopy(order)
        return
    end
    @info("Reviving order failed. Will try again soon.")
end
export check_orders_to_revive