function check_balances(user)
    balances_all  = Dict()
    # Load BNB settings
    BNB_settings = JSON.parsefile(joinpath(Pinguu.base_dir, "BNB_control/BNB_settings.json"))
    for (k,v) in user
        user_id = parse(Int64, k)
        client = user[k]["client"]

        user_config = glob(joinpath(Pinguu.base_dir, "users/$user_id/*/config.json"));
        user_invest = glob(joinpath(Pinguu.base_dir, "users/$user_id/*/config.json"));
        account = client.get_account()["balances"];
        if account !== nothing
            balances = Dict()

            for bal in account
                balances[bal["asset"]] = Dict()
                balances[bal["asset"]]["free"] = parse(Float64, bal["free"])
                balances[bal["asset"]]["locked"] = parse(Float64, bal["locked"])

                #
                ## Check Pinguus
                coin = bal["asset"]
                total_vol = 0
                locked   = 0
                locked_stopped = 0
                invested  = 0
                for c in user_config
                    tmp_config = JSON.parsefile(c)
                    if tmp_config["status"] != "dead" && tmp_config["pureEMA"] == 0
                        stat = JSON.parsefile(joinpath(dirname(c), "status.json"))
                        if stat["base_coin"] == coin
                            oo = JSON.parsefile(joinpath(dirname(c), "open_orders.json"))
                            co = JSON.parsefile(joinpath(dirname(c), "closed_orders.json"))
                            if length(oo["BUY"]) > 0
                                for (k,v) in oo["BUY"]
                                    id_str = split(k, "_")[end]
                                    if v["status"] != "stopped"
                                        locked += parse(Float64, v["price"]) * parse(Float64, v["origQty"])
                                    else
                                        locked_stopped += parse(Float64, v["price"]) * parse(Float64, v["origQty"])
                                    end
                                    for (k,v) in co[id_str]
                                        if v["side"] == "BUY"
                                            invested += parse(Float64, v["cummulativeQuoteQty"])
                                        else
                                            invested -= parse(Float64, v["cummulativeQuoteQty"])
                                        end
                                    end
                                end
                            elseif length(oo["SELL"]) > 0 && length(oo["BUY"]) == 0
                                #
                                ## Case: Bot is fully invested!
                                for (k,v) in oo["SELL"]
                                    id_str = split(k, "_")[end]
                                    for (k,v) in co[id_str]
                                        if v["side"] == "BUY"
                                            invested += parse(Float64, v["cummulativeQuoteQty"])
                                        else
                                            invested -= parse(Float64, v["cummulativeQuoteQty"])
                                        end
                                    end
                                end
                            end

                            for (k,v) in tmp_config["volume"]
                                total_vol += v
                            end
                            total_vol += tmp_config["thes_vol"]
                        end
                    end
                end
                balances[bal["asset"]]["pinguu_locked"]   = locked
                balances[bal["asset"]]["pinguu_locked_stopped"] = locked_stopped
                balances[bal["asset"]]["pinguu_invested"] = invested
                balances[bal["asset"]]["pinguu_volume"]   = total_vol
                #
                ## Check Pinguu Invest
                user_invest = glob(joinpath(Pinguu.base_dir, "invest/users/$user_id/filled/*/*/" * bal["asset"] * "*.json"))
                user_invest_sold = glob(joinpath(Pinguu.base_dir, "invest/users/$user_id/sold/*/*/" * bal["asset"] * "*.json"))
                balances[bal["asset"]]["invest"] = 0
                for inv in user_invest
                    tmp = JSON.parsefile(inv)
                    balances[bal["asset"]]["invest"] += parse(Float64, tmp["amount"])
                end
                for inv in user_invest_sold
                    tmp = JSON.parsefile(inv)
                    balances[bal["asset"]]["invest"] -= parse(Float64, tmp["amount"])
                end
                balances[bal["asset"]]["estimated_free"]  = balances[bal["asset"]]["free"] - balances[bal["asset"]]["invest"] - locked_stopped - (total_vol - invested - locked - locked_stopped)
            end
        end
        
        if haskey(BNB_settings, k)
            # Check if user is registered and uses BNB Control
            if BNB_settings[k]["active"] == 1
                # Get current BNB value
                current = parse(Float64, client.get_ticker(symbol="BNBEUR")["lastPrice"])
                # Calculate amount of EUR that should be kept aside for next BNB purchase
                keep_aside = BNB_settings[k]["val"] + BNB_settings[k]["low_limit"] - balances["BNB"]["estimated_free"]*current
                if keep_aside > 0
                    balances["EUR"]["estimated_free"] -= keep_aside
                end
            end
        end
        
        
        #
        ## Grid Bots
        grid_config_paths = glob(joinpath(Pinguu.base_dir, "grid_bots/user/$user_id/*/config.json"))
        grid_volume, grid_locked, grid_invested, grid_sub_from_free = 0, 0, 0, 0
        for grid_config_path in grid_config_paths
            tmp = JSON.parsefile(grid_config_path)
            if !(tmp["status"] in ["finished", "prep"]) && tmp["testing"] == "0"
#                 total_value = typeof(tmp["total_value"]) == Float64 ? tmp["total_value"] : parse(Float64, tmp["total_value"])
                total_value = Pinguu.get_current_volume(tmp)
                executedQty = typeof(tmp["init_state"]["executedQty"]) == Float64 ? tmp["init_state"]["executedQty"] : parse(Float64, tmp["init_state"]["executedQty"])
                if typeof(tmp["init_state"]["sold"]) != Int64
                    sold = typeof(tmp["init_state"]["sold"]) == Float64 ? tmp["init_state"]["sold"] : parse(Float64, tmp["init_state"]["sold"])
                else
                    sold = float(tmp["init_state"]["sold"])
                end
                cummulativeQuoteQty = typeof(tmp["init_state"]["cummulativeQuoteQty"]) == Float64 ? tmp["init_state"]["cummulativeQuoteQty"] : parse(Float64, tmp["init_state"]["cummulativeQuoteQty"])
                trade_grid = JSON.parsefile(joinpath(dirname(grid_config_path), "trade_grid.json"))
                invested, locked = 0, 0
                for (price, gridpoint) in trade_grid
                    if haskey(gridpoint, "buy_order")
                        tmp_val = gridpoint["buy_order"]["cummulativeQuoteQty"]
                        invested += typeof(tmp_val) == Float64 ? tmp_val : parse(Float64, tmp_val)
                    end
                    if haskey(gridpoint, "side")
                        if gridpoint["side"] == client.SIDE_BUY
                            if haskey(gridpoint, "order")
                                tmp_price = typeof(gridpoint["order"]["price"]) == Float64 ? gridpoint["order"]["price"] : parse(Float64, gridpoint["order"]["price"])
                                tmp_qty   = typeof(gridpoint["order"]["origQty"]) == Float64 ? gridpoint["order"]["origQty"] : parse(Float64, gridpoint["order"]["origQty"])
                                locked += tmp_price * tmp_qty
                            end
                        end
                    end
                end
                sub_from_free = total_value - cummulativeQuoteQty * (1 - sold/executedQty) - invested - locked
                grid_volume += total_value
                grid_locked += locked
                grid_invested += invested
                grid_sub_from_free += sub_from_free
            end
        end
        balances["EUR"]["estimated_free"] -= grid_sub_from_free
        balances["EUR"]["grid_volume"] = grid_volume
        balances["EUR"]["grid_locked"] = grid_locked
        balances["EUR"]["grid_invested"] = grid_invested
        
        balances_all[k] = balances
    end
    open(joinpath(Pinguu.base_dir, "account_balances.json"), "w") do f
        JSON.print(f, balances_all, 4)
    end
    return balances_all
end
export check_balances