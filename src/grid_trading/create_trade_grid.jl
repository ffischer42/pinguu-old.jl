function create_trade_grid(client, config, bot_path)
    if !isfile(joinpath(bot_path, "trade_grid.jl"))
        trade_grid = Dict()
        trade_grid[config["init_state"]["price"]] = Dict("status" => "current")
        cur_price = typeof(config["init_state"]["price"]) != Float64 ? parse(Float64, config["init_state"]["price"]) : config["init_state"]["price"]
        last_price = Pinguu.price2string(cur_price, config["sell_precision"])

        #
        ## Calculate some basics
        cQty  = typeof(config["init_state"]["cummulativeQuoteQty"]) != Float64 ? parse(Float64, config["init_state"]["cummulativeQuoteQty"]) : config["init_state"]["cummulativeQuoteQty"]
        exQty = typeof(config["init_state"]["executedQty"]) != Float64 ? parse(Float64, config["init_state"]["executedQty"]) : config["init_state"]["executedQty"]
        tQty  = typeof(config["total_value"]) != Float64 ? parse(Float64, config["total_value"]) : config["total_value"]
        total_range = typeof(config["grid"]["total_range"]) != Float64 ? parse(Float64, config["grid"]["total_range"]) : config["grid"]["total_range"]
        grid_step   = typeof(config["grid"]["step"]) != Float64 ? parse(Float64, config["grid"]["step"]) : config["grid"]["step"]

        total_steps =  total_range / grid_step
        sell_step_num = floor(total_steps * (cQty / tQty))
        buy_step_num  = floor(total_steps * (1 - cQty / tQty))

        sell_coins = exQty
        sell_step_val = round(sell_coins / sell_step_num, digits=config["precision"])
        buy_coins  = tQty - cQty
        buy_step_val  = round(buy_coins  / buy_step_num, digits=config["precision"])

        place = true
        while sell_coins > 0
            last_price = Pinguu.price2string(cur_price, config["sell_precision"])
            cur_price *= (1+grid_step/100)
            qty = sell_step_val
            if sell_coins - qty < 0
                qty = floor(sell_coins, digits=config["precision"])
                if qty * cur_price <= config["min_qty"]
                    trade_grid[last_price]["qty"] += qty
                    sell_coins = 0
                    continue
                end
            end
            tmp_price = Pinguu.price2string(cur_price, config["sell_precision"])
            trade_grid[tmp_price] = Dict(
                "status" => "wait", "side" => client.SIDE_SELL, "type" => "initial", "qty" => qty, "price" => tmp_price
            )
            if place
                trade_grid[tmp_price]["status"] = "place"
                place = false
            end
            sell_coins -= qty
        end


        buy_coins = tQty - cQty
        cur_price = typeof(config["init_state"]["price"]) != Float64 ? parse(Float64, config["init_state"]["price"]) : config["init_state"]["price"]
        place = true
        while buy_coins > 0
            cur_price *= (1-grid_step/100)
            qty = buy_step_val
            if buy_coins - qty < 0
                qty = floor(buy_coins, digits=config["sell_precision"])
                if qty <= config["min_qty"]
                    buy_coins = 0
                    continue
                end
            end
            buy_qty = floor(qty / cur_price, digits=config["precision"])
            tmp_price = Pinguu.price2string(cur_price, config["sell_precision"])
            trade_grid[tmp_price] = Dict(
                "status" => "wait", "side" => client.SIDE_BUY, "type" => "normal", "value" => qty, "price" => tmp_price, "qty" => buy_qty
            )
            if place
                trade_grid[tmp_price]["status"] = "place"
                place = false
            end
            buy_coins -= qty
        end
    else
        trade_grid = JSON.parsefile(joinpath(bot_path, "trade_grid.jl"))
    end
    return trade_grid
end
export create_trade_grid