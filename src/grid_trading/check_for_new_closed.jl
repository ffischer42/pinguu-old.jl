function check_for_new_closed(client, config, bot_path)
    new_closed = glob(joinpath(bot_path[2:end], "temp/new_closed*.json"))
    if length(new_closed) > 0
        yr, m = split(string(now()), "-")[1:2]
        current_closed_orders_path = joinpath(bot_path, "history/" * yr * "/" * m * ".json")
        !isdir(dirname(current_closed_orders_path)) ? mkpath(dirname(current_closed_orders_path)) : ""

        closed_orders = isfile(current_closed_orders_path) ? JSON.parsefile(current_closed_orders_path) : Dict()
        !haskey(closed_orders, string(today())) ? closed_orders[string(today())] = [] : ""
        #
        ## If testing is active
        test_bot = config["testing"] == "1" ? true : false
        if test_bot
            #
            ## Profit is estimated using the assumption that BNB is used for fee payments
            ### the associated BNB value is subtracted from the raw profit
            for new in new_closed
                tmp = JSON.parsefile(new)
                if tmp["type"] == "normal"
                    paid = tmp["buy_order"]["cummulativeQuoteQty"]
                    got = tmp["order"]["cummulativeQuoteQty"]
                elseif tmp["type"] == "initial"
                    price = typeof(config["init_state"]["price"]) != Float64 ? parse(Float64, config["init_state"]["price"]) : config["init_state"]["price"]
                    got = typeof(tmp["order"]["cummulativeQuoteQty"]) != Float64 ? parse(Float64, tmp["order"]["cummulativeQuoteQty"]) : tmp["order"]["cummulativeQuoteQty"]
                    paid = got * price/parse(Float64, tmp["order"]["price"])
                end
                #
                ## Fees paid using BNB assumed (0.075% per trade)
                fees = (paid + got) * 0.00075
                profit = got - paid - fees
                tmp["profit"] = profit
                # Calculate thes profit and profit percent
                if !haskey(tmp, "current_volume")
                    current_volume = typeof(config["total_value"]) == Float64 ? config["total_value"] : parse(Float64, config["total_value"])
                    if length(config["extra_volume"]) > 0
                        current_volume += sum(config["extra_volume"])
                    end
                    current_volume += config["thes_volume"]
                else
                    current_volume = parse(Float64, config["total_value"])
                end
                tmp["profit_percent"] = tmp["profit"] * 100 / current_volume
                tmp["profit_thes"] = tmp["profit"] * config["thes_factor"]
                

                push!(closed_orders[string(today())], tmp)

                open(current_closed_orders_path, "w") do f
                    JSON.print(f, closed_orders, 4)
                end
                open(new, "w") do f
                    JSON.print(f, tmp, 4)
                end
                
                if tmp["type"] == "normal"
                    mv(new, joinpath(bot_path, "closed_orders/" * basename(new)))
                elseif tmp["type"] == "initial"
                    mv(new, joinpath(bot_path, "closed_init_orders/" * basename(new)))
                end
            end
        else
            #
            ## Real trades
            Pinguu.anaylse_closed_orders(client, config, bot_path; limit=2)
        end
        return 0
    else
        return 1
    end
end
export check_for_new_closed
# checkFrNewClosed(config_paths, users) = @task check_for_new_closed(client, config, status, bot_path)