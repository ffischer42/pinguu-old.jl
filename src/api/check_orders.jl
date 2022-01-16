function check_open_orders_klines(config, open_orders, closed_orders, log, dt, x, high, low)
    
end


function check_open_orders(config, open_orders, closed_orders, log, current)

    if length(keys(open_orders)) > 0
        extra_order_count = parse(Int64, config["extra_order_count"])
        extra_order_exec  = log["extra_order_exec"]
        order_volume = config["order_volume"]
        extra_order_martingale = config["extra_order_martingale"]
        precision = config["precision"]
        extra_order_step = config["extra_order_step"]
        sell_precision = config["sell_precision"]
        stop_loss = parse(Float64, config["stop_loss"])
        fee = config["fee"]
        take_profit = config["take_profit"]
        
        if config["dry_mode"] == "true"

            if current >= parse(Float64, open_orders["SELL"]["price"]) ### TAKE PROFIT
#                 @info("Take profit was executed")
                open_orders["SELL"]["status"] = "FILLED"
                open_orders["SELL"]["updateTime"] = datetime2unix(now())*1000
                open_orders["SELL"]["executedQty"] = open_orders["SELL"]["origQty"]
                closed_orders[string(now())] = copy(open_orders["SELL"])
                open_orders["BUY"]["status"] == "CANCELLED"
                closed_orders[string(now() - Second(1))] = open_orders["BUY"]
                log["extra_order_exec"] = 0
                log["trade_ongoing"] = false
                
                open_orders = Dict()
                
                open("closed_orders.json", "w") do f
                    JSON.print(f, closed_orders, 4)
                end
                open("open_orders.json", "w") do f
                    JSON.print(f, open_orders, 4)
                end
                open("log.json", "w") do f
                    JSON.print(f, log, 4)
                end
                log = Pinguu.daily_log(closed_orders, config)
                #send_notification(config, "take profit", log);


            elseif extra_order_exec < extra_order_count
                if current <= parse(Float64, open_orders["BUY"]["price"]) ### EXTRA ORDER
#                 @info("Extra order was executed")
                    log["extra_order_exec"] += 1
                    closed_orders = JSON.parsefile("closed_orders.json");
                    open_orders = JSON.parsefile("open_orders.json");
                    executed_order = deepcopy(open_orders["BUY"])
                    executed_order["executedQty"] = executed_order["origQty"]
                    executed_order["status"] = "FILLED"
                    executed_order["updateTime"] = datetime2unix(now())*1000
                    failed_order = deepcopy(open_orders["SELL"])
                    failed_order["status"] = "CANCELLED"
                    closed_orders[string(unix2datetime(executed_order["updateTime"]/1000))] = executed_order
                    closed_orders[string(now() - Second(1))] = failed_order
                    open_orders["BUY"]["time"] = datetime2unix(now())*1000
                    open_orders["BUY"]["updateTime"] = datetime2unix(now())*1000
                    open_orders["BUY"]["orderId"] = rand(1:1:1e7)
                    old_quant = parse(Float64, open_orders["BUY"]["origQty"])
                    old_price = parse(Float64, open_orders["BUY"]["price"])
                    new_quant = floor(order_volume * (extra_order_martingale)^extra_order_exec / parse(Float64, open_orders["BUY"]["price"]), digits=precision)
                    open_orders["BUY"]["origQty"] = string(new_quant)
                    open_orders["BUY"]["executedQty"] = "0.0"
                    open_orders["BUY"]["status"] = "NEW"
                    if extra_order_exec != extra_order_count
                        open_orders["BUY"]["price"] = string(round(old_price * (1 - extra_order_step), digits=sell_precision))
                    else
                        open_orders["BUY"]["status"] = "STOPLOSSLIMIT"
                        open_orders["BUY"]["price"] = string(round(parse(Float64, open_orders["SELL"]["price"]) * (100 - stop_loss)/100, digits=sell_precision))
                    end


                    oriqQty_sell = parse(Float64, open_orders["SELL"]["origQty"])
                    newQty_sell  = floor(oriqQty_sell  + old_quant, digits=precision)
                    origPrice_sell = parse(Float64, open_orders["SELL"]["price"])
                    qty_old = 0
                    for i in 0:1:(extra_order_exec-1)
                        qty_old += extra_order_martingale^i
                    end
                    qty_new = extra_order_martingale^extra_order_exec
                    new_price = (qty_old * origPrice_sell + qty_new * old_price * (1 + fee + take_profit/100)) / (qty_old + qty_new)

                    open_orders["SELL"]["time"] = datetime2unix(now())*1000
                    open_orders["SELL"]["updateTime"] = datetime2unix(now())*1000
                    open_orders["SELL"]["orderId"] = rand(1:1:1e7)
                    open_orders["SELL"]["origQty"] = string(newQty_sell)
                    open_orders["SELL"]["price"] = string(round(new_price, digits=sell_precision))

                    open("closed_orders.json", "w") do f
                        JSON.print(f, closed_orders, 4)
                    end
                    open("open_orders.json", "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                    open("log.json", "w") do f
                        JSON.print(f, log, 4)
                    end
                end
#                 send_notification(config, "extra order", log);
            elseif extra_order_exec == extra_order_count ### STOP LOSS
                if current <= parse(Float64, open_orders["SELL"]["price"]) * (100 - parse(Float64, stop_loss))/100
                    open_orders["SELL"]["status"] = "FILLED"
                    open_orders["SELL"]["updateTime"] = datetime2unix(now())*1000
                    open_orders["SELL"]["executedQty"] = open_orders["SELL"]["origQty"]
                    open_orders["SELL"]["price"] = string(round(current, digits=sell_precision))
                    closed_orders[string(now())] = copy(open_orders["SELL"])
                    log["extra_order_exec"] = 0
                    log["trade_ongoing"] = false
                    
                    open_orders = Dict()

                    open("closed_orders.json", "w") do f
                        JSON.print(f, closed_orders, 4)
                    end
                    open("open_orders.json", "w") do f
                        JSON.print(f, open_orders, 4)
                    end
                    open("log.json", "w") do f
                        JSON.print(f, log, 4)
                    end
                    log = Pinguu.daily_log(closed_orders, config)
                    #send_notification(config, "stop loss", log);
                end
            end 
        else
            order = client.get_order(
                symbol=config["symbol"],
                orderId=open_orders["SELL"]["orderId"])
            if order["status"] == "FILLED"
#                 @info("Take profit was executed")
                closed_orders[string(unix2datetime(order["time"]/1000))] = order
                result = client.cancel_order(
                    symbol=config["symbol"],
                    orderId=open_orders["BUY"]["orderId"]);
                open_orders = Dict()
            end
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
            #
        end
    end
    return open_orders, closed_orders, log
end
