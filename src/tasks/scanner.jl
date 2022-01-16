#
## Update active bots

function check_for_new_bots!(config_paths, users)
    config_files = glob(joinpath(Pinguu.base_dir[2:end], "users/*/*/config.json"))
    api = JSON.parsefile("usr/pinguu/api.json")
    telegram = JSON.parsefile(joinpath(Pinguu.base_dir[2:end], "telegram.json"))
    for file in config_files
        tmp = JSON.parsefile(file)
        if "false" == tmp["dry_mode"] && tmp["ws"] == 1 && tmp["status"] != "dead"
            !haskey(config_paths, tmp["symbol"]) ? config_paths[tmp["symbol"]] = [] : ""
            bot_path = joinpath("/", dirname(file))
            user_id = split(split(file, "pinguu_data/users/")[end], "/")[1]
            if haskey(api, user_id) && haskey(tmp, "strategy") && tmp["pureEMA"] == 0
                if !haskey(tmp, "symbols")
                    if !(bot_path in config_paths[tmp["symbol"]])
                        push!(config_paths[tmp["symbol"]], bot_path)
                    end
                else
                    for (k,v) in tmp["symbols"]
                        if !(bot_path in config_paths[k])
                            push!(config_paths[k], bot_path)
                        end
                    end
                end
            end
        end
    end
end
checkForNewBots!(config_paths, users) = @task check_for_new_bots!(config_paths, users)
export check_for_new_bots!


#
## Update active bots (function)

function check_streams(config_paths, binance_websocket_api_manager, data, client, users)
    #
    ## Put currently needed streams in dict
    tmp_markets = Dict()
    
    #
    ## Get current needed streams
    for (k,v) in config_paths
        for bot_path in v
            tmp = JSON.parsefile(joinpath(bot_path, "config.json"))
            if !haskey(tmp_markets, tmp["symbol"]) && tmp["status"] != "dead"
                tmp_markets[tmp["symbol"]] = []
            end
            if tmp["status"] != "dead"
                for condition in tmp["strategy"]["BUY"]["conditions"]
                    kline = tmp["strategy"]["BUY"]["indicators"][condition]["kline"]
                    if !haskey(tmp, "symbols")
                        if !(kline in tmp_markets[tmp["symbol"]])
                            push!(tmp_markets[tmp["symbol"]], kline)
                        end
                    else
                        for (k1,v1) in tmp["symbols"]
                            if !(kline in tmp_markets[k1])
                                push!(tmp_markets[k1], kline)
                            end
                        end
                    end
                end
            end
        end
    end
#     @info("Need to update streams?")
    
    invests = glob(joinpath(Pinguu.base_dir[2:end], "invest/users/*/filled/*/*/*"))
    for invest in invests
        symbol = split(basename(invest), "_")[1]
        if !haskey(tmp_markets, symbol)
            tmp_markets[symbol] = ["kline_1m"]
        else
            if !("kline_1m" in tmp_markets[symbol])
                push!(tmp_markets[symbol], "kline_1m")
            end
        end
    end
    #
    ## Check if a new stream has to start
    for (k,v) in tmp_markets
        for kline in v
            ## Check if stream is running
            create = true
            for (k1,v1) in binance_websocket_api_manager.stream_list
                if uppercase(v1["markets"][1]) == k && v1["channels"][1] == kline && v1["status"] in ["running", "starting", "restarting"]
                    create = false
                elseif uppercase(v1["markets"][1]) == k && v1["channels"][1] == kline
                    create = false
                    binance_websocket_api_manager.set_restart_request()
                end
            end
            if create
                binance_websocket_api_manager.create_stream([kline], [k], stream_label=k * " | " * split(kline, "_")[end], output="UnicornFy")
                !haskey(data, k) ? data[k] = Dict() : ""
                datapoints = 200
                data[k][kline] = Pinguu.get_klines(client, k, kline, datapoints)
            end
        end
    end

    #
    ## Check if a stream has to stop
    for (k,v) in binance_websocket_api_manager.stream_list
        if uppercase(v["markets"][1]) != "!USERDATA"
            kline = v["channels"][1] 
            market = uppercase(v["markets"][1])
            stop_this_stream = false
            if haskey(tmp_markets, market)
                if !(kline in tmp_markets[market])
                    stop_this_stream = true
                end
            else
                stop_this_stream = true
            end
            if stop_this_stream
                binance_websocket_api_manager.stop_stream(k)
                sleep(10)
                binance_websocket_api_manager.delete_stream_from_stream_list(k)
            end
        #
        ## Check for user streams
        elseif uppercase(v["markets"][1]) == "!USERDATA"
            for (k,v) in users
                if v["api_secret"] == v["api_secret"] && v["api_key"] == v["api_key"]
                end
            end
        end
    end
#     @info("Check user streams")
    #
    ## Check for user streams
    for (k,v) in users
        create = true
        for (k1,v1) in binance_websocket_api_manager.stream_list
            if uppercase(v1["markets"][1]) == "!USERDATA"
                if v["api_secret"] == v1["api_secret"] && v["api_key"] == v1["api_key"]
                    create = false
                end
            end
        end
        if create
            binance_websocket_api_manager.create_stream("arr", "!userData", stream_label="User id: " * k,  api_key=v["api_key"], api_secret=v["api_secret"], output="UnicornFy")
        end
    end

end
checkStreams(config_paths, binance_websocket_api_manager, data, client, users) = @task check_streams(config_paths, binance_websocket_api_manager, data, client, users)


#
## Store data task

function store_data(data, symbol, kline_type)
    data_dict = Dict()
    data_dict["time"] = data[symbol][kline_type].close_time
    data_dict["price"] = data[symbol][kline_type].close
    open(joinpath(Pinguu.base_dir, "ticker/" * symbol * "_" * kline_type * "_graph.json"), "w") do f
        JSON.print(f, data_dict, 4)
    end
    if kline_type == "kline_1m"
        tmp = [data[symbol][kline_type].close_time, data[symbol][kline_type].open, data[symbol][kline_type].high, data[symbol][kline_type].low, data[symbol][kline_type].close]
        tmp_data = []
        for i in 1:length(tmp[1])
            push!(tmp_data, [1000 .* datetime2unix.(tmp[1][i]) .+ 1, tmp[2][i], tmp[3][i], tmp[4][i], tmp[5][i]])
        end
        open(joinpath(Pinguu.base_dir, "ticker/" * symbol * "_" * kline_type * "_candle.json"), "w") do f
            JSON.print(f, tmp_data, 4)
        end
    end
end

storedata(data, symbol, kline_type) = @task store_data(data, symbol, kline_type)


#
## Print Task (for notebook)

function print_task(data, kline_type)
    IJulia.clear_output(true)
    plot_symbol = []
    for (k,v) in data
        push!(plot_symbol, plot(v[kline_type].close_time[end-60:end], v[kline_type].close[end-60:end], label="", title=k))
    end
    p = plot(plot_symbol..., size=(1500,800))
    display(p)
end

printtask(data, kline_type) = @task print_task(data, kline_type)


#
## Analyse Task

function analyze_data(data, symbol)
    results = Dict()
    for (k,v) in data[symbol]
        results[k] = Dict()
        #
        ## Bollinger Bands
        results[k]["BB"] = Dict()
        for n in 20:10:50
            results[k]["BB"][string(n)] = Dict()
            for sigma in 1.0:1.0:5.0
                results[k]["BB"][string(n)][string(sigma)] = Indicators.bbands(data[symbol][k].close, n=n, sigma=sigma);
            end
        end

        #
        ## EMA
        results[k]["EMA"] = Dict()
        for n in [8, 13, 21, 55]
            results[k]["EMA"][string(n)] = Indicators.ema(data[symbol][k].close, n=n)
        end
    end
    return results
end
# export analyze_data

function check_for_signal(data, results, symbol, strategy)
    if strategy["BUY"]["type"] == "active"
        signals = []
        for con in strategy["BUY"]["conditions"]
            v = strategy["BUY"]["indicators"][con]
            prices = data[symbol][v["kline"]].close[end-1:end]
            if v["type"] == "BB"

                ## Above
                if v["above"]["active"] == 1
                    n = string(v["above"]["n"])
                    sigma = string(float(v["above"]["sigma"]))
                    bb_high = results[v["kline"]]["BB"][n][sigma][:,3][end-1:end]
                    if prices[2] >= bb_high[2] && prices[1] < bb_high[1]
                        push!(signals, con)
                    end
                end

                ## Below
                if v["below"]["active"] == 1 && !(con in signals)
                    n = string(v["below"]["n"])
                    sigma = string(float(v["below"]["sigma"]))
                    bb_low = results[v["kline"]]["BB"][n][sigma][:,1][end-1:end]
                    if prices[2] < bb_low[2]
                        push!(signals, con)
                    end
                end
            elseif v["type"] == "EMA"
                levels = sort(v["levels"])
                level = []
                for lvl in levels
                    if string(lvl) in keys(results[v["kline"]]["EMA"])
                        push!(level, results[v["kline"]]["EMA"][string(lvl)][end-1:end])
                    end
                end
                if length(levels) == 4
                    if v["trigger"] == "transition"
                        if level[1][2] > level[2][2] > level[3][2] > level[4][2] && level[1][2] > level[2][2] > level[3][2] <= level[4][2]
                            push!(signals, con)
                        end
                    elseif v["trigger"] == "trend"
                        if level[1][2] > level[2][2] > level[3][2] > level[4][2]
                            push!(signals, con)
                        end
                    end                
                end
            end
        end

        ## Decision
        if strategy["BUY"]["union"] == 0
            buy_signal = length(signals) > 0 ? true : false
        else
            buy_signal = length(signals) == length(strategy["BUY"]["conditions"]) ? true : false
        end
        buy_note = ""
        for s in signals
            buy_note *= s
        end
    end
    sell_signal = false
    sell_note = ""
    return buy_signal, sell_signal, buy_note, sell_note
end
# export check_for_signal

function analyse_task(data, symbol, config_paths)
    check_paths = Dict()
    for (symbol, paths) in config_paths
        for bot_path in paths
            config = JSON.parsefile(joinpath(bot_path, "config.json"))
            open_orders = JSON.parsefile(joinpath(bot_path, "open_orders.json"))
            if length(open_orders["NEW"]) == 0 && length(open_orders["BUY"]) == 0 && 
                length(open_orders["SELL"]) == 0
                check_paths[symbol] = paths
            end
            if isfile(joinpath(bot_path, "manual_order.json"))
                check_paths[symbol] = paths
            end
        end
    end
    for (symbol, paths) in check_paths
        results = analyze_data(data, symbol)
        for bot_path in paths
            config = JSON.parsefile(joinpath(bot_path, "config.json"))
            if config["status"] == "active"
                open_orders = JSON.parsefile(joinpath(bot_path, "open_orders.json"))

                if length(open_orders["NEW"]) == 0 && length(open_orders["BUY"]) == 0 && length(open_orders["SELL"]) == 0 && !isfile(joinpath(bot_path, "manual_order.json"))
                    buy, sell, buy_note, sell_note = check_for_signal(data, results, symbol, config["strategy"])
                    if buy
                        open_orders["NEW"]["time"] = now()
                        open_orders["NEW"]["trigger"] = buy_note
                        open(joinpath(bot_path, "open_orders.json"), "w") do f
                            JSON.print(f, open_orders, 4)
                        end
                    end
                    if sell
                        #
                        ## EMA Bot 

                    end
                elseif length(open_orders["NEW"]) == 0 && length(open_orders["BUY"]) == 0 && length(open_orders["SELL"]) == 0 && isfile(joinpath(bot_path, "manual_order.json"))
                    tmp = JSON.parsefile(joinpath(bot_path, "manual_order.json"))
                    open_orders["NEW"]["time"] = tmp["time"]
                    open_orders["NEW"]["trigger"] = tmp["trigger"]
                    open(joinpath(bot_path, "open_orders.json"), "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                    rm(joinpath(bot_path, "manual_order.json"))
                elseif isfile(joinpath(bot_path, "manual_order.json"))
                    rm(joinpath(bot_path, "manual_order.json"))
                end
            end
        end
    end
end
# export analyse_task
    
analysetask(data, symbol, config_paths) = @task analyse_task(data, symbol, config_paths)