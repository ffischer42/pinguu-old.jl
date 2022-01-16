function get_profit_for_single_day(u::String="*", eval_date::String=string(today()))
    yr, m, d = split(eval_date, "-")
    tmp = glob(joinpath(Pinguu.base_dir, "users/" * u * "/*/closed_orders/$yr/$m.json"));
    profit = 0
    for file in tmp
        month = JSON.parsefile(file)
        for (day, info) in month
            if day == eval_date
                for (id_str, trade) in info["trades"]
                    profit += haskey(trade, "profit_EUR") ? trade["profit_EUR"] : trade["profit"]
                end
            end
        end
    end
    grid_bot_paths = glob(joinpath(Pinguu.base_dir, "grid_bots/user/" * u * "/*/config.json"))
    for grid_bot_path in grid_bot_paths
        tmp_config = JSON.parsefile(grid_bot_path)
        if tmp_config["testing"] == "0"
            tmp = glob(joinpath(dirname(grid_bot_path), "history/$yr/$m.json"))
            for file in tmp
                month = JSON.parsefile(file)
                for (day, info) in month
                    if day == eval_date
                        for trade in info
                            profit += trade["profit"]
                        end
                    end
                end
            end
        end
    end
    return profit
end
export get_profit_for_single_day

function get_profit_for_past_days(u::String="*", days_num=30)
    past_days = []
    profits = []
    for num in 0:1:days_num-1
        eval_date = string(today() - Day(num))
        push!(past_days, eval_date)
        push!(profits, Pinguu.get_profit_for_single_day(u, eval_date))
    end
    return past_days, profits
end
export get_profit_for_past_days

function get_profit_for_past_months(u::String="*", months_num=7)
    past_months = []
    profits = []

    for num in 0:1:months_num-1
        eval_date = string(today()-Month(num))
        yr, m, d = split(eval_date, "-")
        #
        ## Pinguus
        tmp = glob(joinpath(Pinguu.base_dir, "users/" * u * "/*/closed_orders/$yr/$m.json"));
        profit = 0
        for file in tmp
            month = JSON.parsefile(file)
            for (day, info) in month
                if haskey(info, "trades")
                    for (id_str, trade) in info["trades"]
                        profit += haskey(trade, "profit_EUR") ? trade["profit_EUR"] : trade["profit"]
                    end
                end
            end
        end
        #
        ## Grid bots
        grid_bot_paths = glob(joinpath(Pinguu.base_dir, "grid_bots/user/" * u * "/*/config.json"))
        for grid_bot_path in grid_bot_paths
            tmp_config = JSON.parsefile(grid_bot_path)
            if tmp_config["testing"] == "0"
                tmp = glob(joinpath(dirname(grid_bot_path), "history/$yr/$m.json"))
                for file in tmp
                    month = JSON.parsefile(file)
                    for (day, info) in month
                        for trade in info
                            profit += trade["profit"]
                        end
                    end
                end
            end
        end 
            
        push!(past_months, yr * "-" * m)
        push!(profits, profit)
    end
    return past_months, profits
end
export get_profit_for_past_months