function get_total_profit(u::String="*")
    tmp = glob(joinpath(Pinguu.base_dir, "users/" * u * "/*/closed_orders/*/*.json"));
    total_profit = 0
    #
    ## Pinguus
    for file in tmp
        month = JSON.parsefile(file)
        for (day, info) in month
            if !(day in ["profit" "trade_num"])
                for (id_str, trade) in info["trades"]
                    total_profit += haskey(trade, "profit_EUR") ? trade["profit_EUR"] : trade["profit"]
                end
            end
        end
    end
    #
    ## Grid bots
    tmp = glob(joinpath(Pinguu.base_dir, "grid_bots/user/" * u * "/*/config.json"));
    for grid_bot_path in tmp
        tmp_config = JSON.parsefile(grid_bot_path)
        if tmp_config["testing"] == "0"
            tmp_history = glob(joinpath(dirname(grid_bot_path), "history/*/*json"))
            for tmp_history_file in tmp_history
                month = JSON.parsefile(tmp_history_file)
                for (day, trades) in month
                    for trade in trades
                        total_profit += trade["profit"]
                    end
                end
            end
            
        end
    end
    return total_profit
end
export get_total_profit