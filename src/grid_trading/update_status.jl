function update_status(client, config, bot_path)
    files = glob(joinpath(bot_path[2:end], "history/*/*.json"))
    profit = 0
    trade_num = 0
    sold = 0
    for file in files
        tmp = JSON.parsefile(file)
        for (day,trades) in tmp
            for trade in trades
                profit += trade["profit"]
                trade_num += 1
                if trade["type"] == "initial"
                    sold += typeof(trade["order"]["executedQty"]) == Float64 ? trade["order"]["executedQty"] : parse(Float64, trade["order"]["executedQty"])
                end
            end
        end
    end
    if !haskey(config["init_state"], "sold")
        config["init_state"]["sold"] = 0
    end
    if config["init_state"]["sold"] != sold
        config["init_state"]["sold"] = sold
        open(joinpath(bot_path, "config.json"), "w") do f
            JSON.print(f, config, 4)
        end
    end
    trade_grid = JSON.parsefile(joinpath(bot_path, "trade_grid.json"))
    current_price = findfirst(x->x["status"] == "current", trade_grid)
    current_gridpoint = findfirst(x->x == current_price, sort(string.(keys(trade_grid))))
    
    next_gridpoints = Pinguu.get_next_gridpoints(trade_grid, current_price)
    
    ticker, current_ticker = Pinguu.get_current_ticker(client, config, use_api=true)
    next_sell = findall(x -> x["status"] == "check" && x["side"] == client.SIDE_SELL, trade_grid)
    if length(next_sell) > 0
        next_sell = next_sell[1]
        to_sell = round(100*(1 - current_ticker / parse(Float64, next_sell)), digits=2)
    else
        to_sell = 0
    end
    
    
    #
    ## APR
    files = glob(joinpath(bot_path[2:end], "history/*/*.json"));
    total_profit_percent = 0
    profit_thes = 0
    for file in files
        tmp = JSON.parsefile(file)
        for (day, trades) in tmp
            for trade in trades
                total_profit_percent += trade["profit_percent"]
                profit_thes += trade["profit_thes"]
            end
        end
    end
    timespan = now() - DateTime(config["start"])
    rendite = total_profit_percent / (timespan.value/(1000*3600*24*365))
    trade_num_h = trade_num / (timespan.value/(1000*3600))
    trade_num_d = trade_num / (timespan.value/(1000*3600*24))
    if config["thes_volume"] != round(profit_thes, digits=config["sell_precision"])
        config["thes_volume"] = round(profit_thes, digits=config["sell_precision"])
        open(joinpath(bot_path, "config.json"), "w") do f
            JSON.print(f, config, 4)
        end
    end
    
    
    #
    ## Currently invested in coin
    bought = config["init_state"]["cummulativeQuoteQty"] * (1-config["init_state"]["sold"] / config["init_state"]["executedQty"])
    for (k,v) in trade_grid
        if haskey(v, "buy_order")
            bought += typeof(v["buy_order"]["cummulativeQuoteQty"]) == Float64 ? v["buy_order"]["cummulativeQuoteQty"] : parse(Float64, v["buy_order"]["cummulativeQuoteQty"])
        end
    end
    
    #
    ## Daily average profit
    current_value = Pinguu.get_current_volume(config)
    daily_avg = (current_value * rendite/100)/365
    
    #
    ## Today profit
    today_profit = 0
    yr, m, d = split(string(today()), "-")
    profit_file = joinpath(bot_path[2:end], "history/" * yr * "/" * m * ".json")
    if isfile(profit_file)
        tmp = JSON.parsefile(profit_file)
        if haskey(tmp,string(today()))
            for trade in tmp[string(today())]
                today_profit += trade["profit"]
            end
        end
    end
    
    #
    ## Status dictionary
    if haskey(next_gridpoints, "BUY") 
        progress_line = round((current_ticker - parse(Float64, next_gridpoints["BUY"]))/((parse(Float64, next_gridpoints["SELL"]) - parse(Float64, next_gridpoints["BUY"]))/100))
    else
        progress_line = 0
    end
    
    status = Dict(
        "name"              => config["name"],
        "uuid"              => config["uuid"],
        "total_value"       => config["total_value"],
        "bought"            => bought,
        "profit"            => profit,
        "today_profit"      => today_profit,
        "daily_avg"         => daily_avg,
        "trade_num"         => trade_num,
        "trade_num_d"       => round(trade_num_d, digits=1),
        "trade_num_h"       => round(trade_num_h, digits=1),
        "time"              => string(now()),
        "current_gridpoint" => current_gridpoint,
        "gridpoint_num"     => length(trade_grid),
        "to_sell"           => to_sell,
        "progress_line"     => progress_line,
        "rendite"           => rendite,
        "profit_thes"       => profit_thes,
        "thes_factor"       => config["thes_factor"],
        "current_volume"    => current_value
    )

    if haskey(next_gridpoints, "BUY") 
        status["next_buy"] = next_gridpoints["BUY"]
        progress_line = 
        round((current_ticker - parse(Float64, next_gridpoints["BUY"]))/((parse(Float64, next_gridpoints["SELL"]) - parse(Float64, next_gridpoints["BUY"]))/100))
    else
        progress_line = 0
    end
    if haskey(next_gridpoints, "SELL") 
        status["next_sell"] = next_gridpoints["SELL"]
    end
    
    
    
    open(joinpath(bot_path, "status.json"), "w") do f
        JSON.print(f, status, 4)
    end
    
    return profit, trade_num, sold
end
export update_status


function create_grid_super_status()
    user_paths = glob(joinpath(Pinguu.base_dir , "grid_bots/user/*"));
    super_status = Dict()
    for user_path in user_paths
        status_paths = glob(joinpath(user_path, "*/status.json"))
        for status_path in status_paths
            status = JSON.parsefile(status_path)
            config = JSON.parsefile(joinpath(split(status_path, "status.json")[1], "config.json"))
            status["config"] = config
            
            user_id = split(user_path, "/")[end]
            !haskey(super_status, user_id) ? super_status[user_id] = Dict("active" => [], "inactive" => []) : ""
            if config["status"] == "active"
                push!(super_status[user_id]["active"], status)
            else
                push!(super_status[user_id]["inactive"], status)                
            end
        end
    end
    open(joinpath(Pinguu.base_dir, "stats/grid_super_status.json"), "w") do f
        JSON.print(f, super_status, 4)
    end
end
export create_grid_super_status


function create_bots_super_status()
    user_paths = glob(joinpath(Pinguu.base_dir , "users/*"));
    super_status = Dict()
    for user_path in user_paths
        status_paths = glob(joinpath(user_path, "*/status.json"))
        for status_path in status_paths
            status = JSON.parsefile(status_path)
            config = JSON.parsefile(joinpath(split(status_path, "status.json")[1], "config.json"))
            status["config"] = config
#             delete!(status, "plotting")
                
            user_id = split(user_path, "/")[end]
            !haskey(super_status, user_id) ? super_status[user_id] = Dict("active" => [], "inactive" => []) : ""
            if config["status"] in ["active", "pause", "stop"]
                push!(super_status[user_id]["active"], status)
            else
                push!(super_status[user_id]["inactive"], status)                
            end
        end
    end
    open(joinpath(Pinguu.base_dir, "stats/bots_super_status.json"), "w") do f
        JSON.print(f, super_status, 4)
    end
end
export create_bots_super_status