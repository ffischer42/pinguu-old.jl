function examine_order(closed_order, id_str, client, config, bot_path)
    tmp_order = deepcopy(closed_order)
    order_check = Dict()
    order_check["orders"] = tmp_order

    tmp_pro    = 0
    order_check      = Dict()
    order_check["buys_exec"]  = 0
    order_check["total_vol"]  = 0
    order_check["use_vol"]    = 0
    order_check["commission"] = 0
    order_check["commission_coin"] = 0
    order_check["buy_vol"] = 0
    order_check["sell_vol"] = 0
    for (k2, v2) in tmp_order
        buy_sign = 1
        if v2["side"] == "BUY"
            order_check["buys_exec"] += 1
            buy_sign = -1
        end
        sleep(0.3)
        if !haskey(v2, "trades")
            trades = try client.get_my_trades(symbol=v2["symbol"], orderId=v2["orderId"])
                catch  
                @info("Getting trades failed.")
                return
            end
            v2["trades"] = trades
            v2 = try add_fees_to_closed_order(v2, config, bot_path, client)
                catch 
                @info("Adding fees failed.")
                return
            end
            closed_orders = JSON.parsefile(joinpath(bot_path, "closed_orders.json"));
            closed_orders[id_str][k2] = v2
            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                JSON.print(f, closed_orders, 4)
            end
        else
            for trade in v2["trades"]                    
            @info("Trades already exist")
                if !haskey(trade, "com")                    
                    @info("No comissions stored")
                    v2 = try add_fees_to_closed_order(v2, config, bot_path, client)
                        catch 
                        @info("Adding fees failed.")
                        return
                    end
                    closed_orders = JSON.parsefile(joinpath(bot_path, "closed_orders.json"));
                    closed_orders[id_str][k2] = v2
                    open(joinpath(bot_path, "closed_orders.json"), "w") do f
                        JSON.print(f, closed_orders, 4)
                    end
                end
            end
        end

        for t in v2["trades"]
            tmp_pro += buy_sign * parse(Float64, t["quoteQty"])
            tmp_pro -= t["com"]
            if buy_sign > 0
                order_check["sell_vol"] += parse(Float64, t["qty"])
            else
                order_check["buy_vol"] += parse(Float64, t["qty"])
            end
            order_check["total_vol"]  += -1 * buy_sign * parse(Float64, t["qty"])
            order_check["use_vol"]    += -1 * buy_sign * parse(Float64, t["qty"])
            if t["commissionAsset"] == config["farm_coin"]
                order_check["use_vol"] -= t["com_coin"]
            end 
            order_check["commission"] += t["com"]
            order_check["commission_coin"] += t["com_coin"]
        end
        closed_orders = JSON.parsefile(joinpath(bot_path, "closed_orders.json"));
        if tmp_order != closed_orders[id_str]
            closed_orders[id_str] = tmp_order
            open(joinpath(bot_path, "closed_orders.json"), "w") do f
                JSON.print(f, closed_orders, 4)
            end
        end
    end
    order_check["current_profit"] = tmp_pro
    order_check["price_correction"]  = order_check["total_vol"] / order_check["use_vol"]
    return order_check
end
export examine_order