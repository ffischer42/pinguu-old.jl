function BNB_control(user, balances_all; 
        settings_path=joinpath(Pinguu.base_dir, "BNB_control/BNB_settings.json"))
    acc = JSON.parsefile(settings_path)
    prices = Dict()
    for (user_id, v) in user
        if haskey(acc, user_id)
            client = user[user_id]["client"]
            if !haskey(acc[user_id], "order")
                acc[user_id]["order"] = Dict()
                open(settings_path, "w") do f
                    JSON.print(f, acc, 4)
                end
            end
            if acc[user_id]["active"] == 1
                @info("---")
                @info("User: " * user_id)
                sleep(0.25)
                if !haskey(prices, acc[user_id]["symbol"])
                    ticker = client.get_ticker(symbol=acc[user_id]["symbol"])["lastPrice"]
                    price = parse(Float64, ticker)
                    prices[acc[user_id]["symbol"]] = Dict()
                    prices[acc[user_id]["symbol"]]["price"] = price
                    prices[acc[user_id]["symbol"]]["ticker"] = ticker
                else
                    price  = prices[acc[user_id]["symbol"]]["price"]
                    ticker = prices[acc[user_id]["symbol"]]["ticker"]
                end
                
                if balances_all[user_id]["BNB"]["estimated_free"] * price < acc[user_id]["low_limit"] && length(acc[user_id]["order"]) == 0
                    #
                    ##
                    ###
                    # If BNB level is low & no order ongoing => Check if enough base money is available
                    if balances_all[user_id][acc[user_id]["base_coin"]]["estimated_free"] <= acc[user_id]["val"]
                        @info(string("Base volume not sufficient: ", round(balances_all[user_id][acc[user_id]["base_coin"]]["estimated_free"], digits=2), " ", acc[user_id]["base_coin"]))
                        continue
                    end
                    qty = ceil(acc[user_id]["val"]/price, digits=3)
                    sleep(0.5)
                    result = try client.order_market_buy(
                        symbol=acc[user_id]["symbol"],
                        quantity=qty);
                        catch
                        @info("order_market_buy failed")
                        nothing
                    end
                    if result !== nothing
                        acc[user_id]["order"] = result
                        open(settings_path, "w") do f
                            JSON.print(f, acc, 4)
                        end
                    end
                    if user_id == "1"
                        telegram = JSON.parsefile(joinpath(Pinguu.base_dir, "telegram.json"))
                        msg = "[BNB Control] Kauf getätigt!"
                        TelegramClient(Pinguu.telegram; chat_id=telegram[user_id])
                        sendMessage(text = msg)
                    end
                elseif length(acc[user_id]["order"]) != 0
                    #
                    ##
                    ###
                    # Check ongoing order
                    order = try client.get_order(
                        symbol=acc[user_id]["symbol"],
                        orderId=acc[user_id]["order"]["orderId"])
                    catch 
                        @info("get_order failed")
                        nothing
                    end
                    if order !== nothing
                        if order["status"] == client.ORDER_STATUS_FILLED
                            yr,m,d = split(string(today()), "-")
                            filename = joinpath(Pinguu.base_dir * "BNB_control/users/" * user_id * "/closed_orders/" * yr * "/" * m * "/", "closed_" * string(now()) * ".json")
                            !isdir(dirname(filename)) ? mkpath(dirname(filename)) : ""
                            open(filename, "w") do f
                                JSON.print(f, order, 4)
                            end
                            acc[user_id]["order"] = Dict()
                            open(settings_path, "w") do f
                                JSON.print(f, acc, 4)
                            end
                            if user_id == "1"
                                telegram = JSON.parsefile(joinpath(Pinguu.base_dir, "telegram.json"))
                                msg = "[BNB Control] Kauf abgeschlossen!"
                                TelegramClient(Pinguu.telegram; chat_id=telegram[user_id])
                                sendMessage(text = msg)
                            end
                        else
                            @info("Order status: " * order["status"])
                        end
                    end
                else
                    #
                    ##
                    ###
                    # Nothing to do
                    @info(string("BNB level: ", round(balances_all[user_id]["BNB"]["estimated_free"] * price, digits=2), " ", acc[user_id]["base_coin"]))
                    @info(string("BNB low limit: ", round(acc[user_id]["low_limit"], digits=2), " ", acc[user_id]["base_coin"]))
                end
            end
        end
    end
end
export BNB_control