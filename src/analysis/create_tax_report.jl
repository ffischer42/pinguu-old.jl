function create_tax_report_bots(usr, Y, M, client)
    files = glob(joinpath(Pinguu.base_dir, "users/" * usr["user_id"] * "/*/closed_orders/$Y/$M.json"))
    if length(files) > 0 
        repeat = 1
        while repeat > 0
            @info("Repeat: " * string(repeat))
            repeat = 1
            for file in files
                tmp = JSON.parsefile(file)
                config = JSON.parsefile(joinpath(split(file, "closed_orders")[1], "config.json"))
                for (k,v) in tmp
                    if !(k in ["trade_num", "profit"])
                        for (k1,v1) in v["trades"]
                            filename = joinpath(joinpath(split(file, "closed_orders")[1], "tax/$Y/$M"), k1 * ".json")
                            if !isfile(filename)
                                entry = Dict()
                                entry["buy"] = []
                                entry["sell"] = []
                                skip = false
                                for (k2,v2) in v1["orders"]
                                    sleep(0.5)
                                    if !haskey(v2, "trades")
                                        trades = try client.get_my_trades(symbol=v2["symbol"], orderId=v2["orderId"])
                                            catch 
                                            sleep(2)
                                            try client.get_my_trades(symbol=v2["symbol"], orderId=v2["orderId"])
                                            catch
                                                sleep(2)
                                                nothing
                                            end
                                        end
                                    else
                                        trades = v2["trades"]
                                    end
                                    if trades == nothing
                                        skip = true
                                    else
                                        if v2["side"] == "BUY"
                                            append!(entry["buy"], trades)
                                        else
                                            append!(entry["sell"], trades)
                                        end
                                    end
                                end
                                if !skip
                                    entry["profit"] = 0
                                    entry["commission"] = 0
                                    for (side, trades) in entry
                                        if side in ["buy", "sell"]
                                            for trade in trades
                                                commission = parse(Float64, trade["commission"])
                                                if commission != 0
                                                    if trade["commissionAsset"] == config["farm_coin"]
                                                        commission *= parse(Float64, trade["price"])
                                                    elseif trade["commissionAsset"] != config["base_coin"]
                                                        translator = string(trade["commissionAsset"], config["base_coin"])
                                                        from = split(string(unix2datetime(trade["time"]/1000)), ".")[1]
                                                        to = split(string(unix2datetime(trade["time"]/1000) + Minute(1)), ".")[1]

                                                        klines = client.get_historical_klines(translator, client.KLINE_INTERVAL_1MINUTE, from, to)
                                                        tt = Pinguu.klines2table(klines, time_warp=0)

                                                        commission *= tt[1].close
                                                    end
                                                end
                                                buy_sign = side == "buy" ? -1 : 1
                                                entry["profit"] += buy_sign * parse(Float64, trade["quoteQty"])
                                                entry["profit"] -= commission
                                                entry["commission"] += commission
                                            end
                                        end
                                        entry["sell_time"] = string(unix2datetime(entry["sell"][end]["time"]/1000))
                                        !isdir(dirname(filename)) ? mkpath(dirname(filename)) : ""
                                        open(filename, "w") do f
                                            JSON.print(f, entry, 4)
                                        end
                                    end
                                else
                                    repeat += 1
                                end
                            end
                        end
                    end
                end
            end
            repeat -= 1
        end
    end
    files = glob(joinpath(Pinguu.base_dir, "users/" * usr["user_id"] * "/*/tax/$Y/$M/*.json"))

    df = DataFrame(Handelsende = [], Profit = [], Gebuehren = [], Symbol = [], A = [], B = [], Kaeufe = [], Verkaeufe = [])
    push!(df, ["", "", "", "", "", "", "", "", ])
    profit = 0
    for file in files
        entry = JSON.parsefile(file)
        push!(df, [
                entry["sell_time"],
                entry["profit"],
                entry["commission"],
                entry["sell"][end]["symbol"],
                "",
                "",
                entry["buy"],
                entry["sell"],
                ])
        profit += entry["profit"]
    end
    push!(df, ["", "", "", "", "", "", "", "", ])
    push!(df, ["Gesamtprofit:", round(profit, digits=3), "EUR", "", "", "", "", "", ]);
    
    filename = joinpath(Pinguu.base_dir, "stats/tax/user/" * usr["user_id"] * "/bots/$Y/$Y-$M.csv")
    !isdir(dirname(filename)) ? mkpath(dirname(filename)) : ""
    if length(files) > 0
        CSV.write(filename, df, delim=";")
    end
end
export create_tax_report_bots


function create_tax_report_grid(usr, Y, M)
    config_files = glob(joinpath(Pinguu.base_dir, "grid_bots/user/" * usr["user_id"] * "/*/config.json"))
    bot_paths = []
    for file in config_files
        tmp = JSON.parsefile(file)
        if tmp["testing"] == "0"
            push!(bot_paths, dirname(file))
        end
    end
    df = DataFrame(Handelsende = [], Profit = [], Gebuehren = [], Symbol = [], A = [], B = [], Kaeufe = [], Verkaeufe = [])
    push!(df, ["", "", "", "", "", "", "", "", ])
    profit = 0
    for bot_path in bot_paths
        files = glob(joinpath(bot_path, "history/$Y/$M.json"))
        tmp_config = JSON.parsefile(joinpath(bot_path, "config.json"))
        for file in files
            tmp = JSON.parsefile(file)
            for (day, trades) in tmp
                for trade in trades
                    sell_time = typeof(trade["order"]["time"]) == Int64 ? unix2datetime(trade["order"]["time"]/1000) : trade["order"]["time"]
                    entry = Dict(
                        "sell_time" => sell_time,
                        "profit" => trade["profit"],
                        "commission" => trade["fee"],
                        "symbol" => trade["order"]["symbol"],
                        "sell" => trade["order"],
                    )
                    if trade["type"] == "normal"
                        entry["buy"] = trade["buy_order"]
                    else
                        entry["buy"] = tmp_config["init_state"]["order"]
                    end

                    push!(df, [
                        entry["sell_time"],
                        entry["profit"],
                        entry["commission"],
                        entry["symbol"],
                        "",
                        "",
                        entry["buy"],
                        entry["sell"],
                    ])
                    profit += trade["profit"]
                end
            end
        end
    end
    push!(df, ["", "", "", "", "", "", "", "", ])
    push!(df, ["Gesamtprofit:", round(profit, digits=3), "EUR", "", "", "", "", "", ]);
    filename = joinpath(Pinguu.base_dir, "stats/tax/user/" * usr["user_id"] * "/grid_bots/$Y/$Y-$M.csv")
    !isdir(dirname(filename)) ? mkpath(dirname(filename)) : ""
    if profit != 0
        CSV.write(filename, df, delim=";")
    end
end
export create_tax_report_grid


function tax_summary(usr, Y)
    profit = 0
    trade_num = 0
    months = []

    for M in lpad.(1:12, 2, "0")
        #
        ## Bots
        files = glob(joinpath(Pinguu.base_dir, "users/" * usr["user_id"] * "/*/tax/$Y/$M/*.json"))
        tmp_profit = 0
        for file in files
            entry = JSON.parsefile(file)
            tmp_profit += entry["profit"]
            trade_num += 1
        end

        #
        ## Grid Bots
        config_files = glob(joinpath(Pinguu.base_dir, "grid_bots/user/" * usr["user_id"] * "/*/config.json"))
        bot_paths = []
        for file in config_files
            tmp = JSON.parsefile(file)
            if tmp["testing"] == "0"
                push!(bot_paths, dirname(file))
            end
        end
        
        for bot_path in bot_paths
            files = glob(joinpath(bot_path, "history/$Y/$M.json"))
            for file in files
                tmp = JSON.parsefile(file)
                for (day, trades) in tmp
                    for trade in trades
                        sell_time = typeof(trade["order"]["time"]) == Int64 ? unix2datetime(trade["order"]["time"]/1000) : trade["order"]["time"]
                        trade_num += 1
                        tmp_profit += trade["profit"]
                    end
                end
            end
        end
        
        profit += tmp_profit
        if tmp_profit != 0
            push!(months, tmp_profit)
        end
    end
    summary = Dict(
        "profit" => profit,
        "trade_num" => trade_num,
        "avg_month" => mean(months)
    )
    filename = joinpath(Pinguu.base_dir, "stats/tax/user/" * usr["user_id"] * "/$Y-summary.json")
    open(filename, "w") do f
        JSON.print(f, summary, 4)
    end
end
export tax_summary


function create_tax_report(usr, Y, M)
    client = usr["client"]
    Pinguu.create_tax_report_grid(usr, Y, M)
    Pinguu.create_tax_report_bots(usr, Y, M, client)
    Pinguu.tax_summary(usr, Y)
end
export create_tax_report