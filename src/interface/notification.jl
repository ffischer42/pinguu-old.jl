function send_notification(filename)
    msg = JSON.parsefile(filename)
    TelegramClient(msg["token"]; chat_id=msg["chat_id"])
    result = try sendMessage(text = msg["str"])
        catch nothing
    end
    if result !== nothing
        rm(filename)
    end
end
export send_notification

function create_notification(notification_type, config, usr; params = Dict(), notification_folder = joinpath(Pinguu.base_dir[2:end], "notification/"))
    chat_id_check = haskey(usr, "telegram")
    if config["notification"]["status"] == "true" && chat_id_check
        msg = Dict()
        msg["token"]   = ENV["telegram"]
        msg["chat_id"] = usr["telegram"]
        msg["type"]    = notification_type
        
        bot_str = "{" * config["name"] * "} "
        msg_str = ""
        pinguus = [
            "\r\n (o_\r\n// \\\r\nV_/_ ",
            "\r\n_o)\r\n// \\\r\nV_/_ ",
            "\r\n (O_\r\n// \\\r\nV_/_",
            "\r\n                (o_\r\n(o_  (o_  // \\\r\n(/)_ (/)_ V_/_ "
        ]
        i = rand(eachindex(pinguus))
        sell_precision = config["base_coin"] == "EUR" ? 2 : config["sell_precision"]
        
        if notification_type == "buy exec"         && config["notification"]["buy_exec"] == true
            
            msg_str = bot_str *  " BUY wurde ausgeführt!\r\nOrder: " * string(params["extra_iteration"]) * "\r\nOrder Volumen: " * params["executedQty"] * " " * config["farm_coin"]
            
        elseif notification_type == "partial buy exec"         && usr["user_id"] == "1"
            
            msg_str = bot_str *  " PARTIAL BUY wurde ausgeführt!\r\nOrder: " * string(params["extra_iteration"]) * "\r\nOrder Volumen: " * params["executedQty"] * " " * config["farm_coin"]
            
        elseif notification_type == "take profit"  && config["notification"]["take_profit"] == true
            
            msg_str = bot_str *  " Take profit!\r\nProfit: " * format(params["val"], precision=sell_precision) * " " * params["coin"] * pinguus[i]
            
        elseif notification_type == "new cycle"    && config["notification"]["new_cycle"] == true
            
            msg_str = bot_str *  " Neuer Zyklus wurde begonnen. \r\nPreis: " * params["ticker"] * " " * config["base_coin"]
            
        elseif notification_type == "cycle closed" && config["notification"]["general_info"] == true
            
            msg_str = bot_str *  " Der Zyklus wurde abgebrochen. Es wird auf ein neues Signal gewartet."
            
        elseif notification_type == "no volume"    && config["notification"]["general_info"] == true
            
            msg_str = bot_str *  " Dein Order Volumen ist aufgebraucht. Bis zum Verkauf wird dieser Bot nichts mehr tun."
            
        elseif notification_type == "testing" 
            
            msg_str = bot_str * pinguus[i]
            
        end
        msg["str"] = msg_str
        if msg["str"] != ""
            id   = string(now()) * "-" * lpad(Int(rand(1:1:1e9)), 6, "0") * ".json"
            file = joinpath(notification_folder, id)
            open(file, "w") do f
                JSON.print(f, msg, 4)
            end
        end
    end
end
export create_notification


function send_daily_summary(user_id, telegram_id)
    day = string(today() - Day(1))
    yr,m,d = split(day, "-")
    closed_files = glob(joinpath(Pinguu.base_dir[2:end], "users/" * string(user_id) * "/*/closed_orders/" * yr * "/" * m * ".json"))
    day_profit = 0
    bot_profits = Dict()
    for closed in closed_files
        tmp = JSON.parsefile(closed)
        if haskey(tmp, day)
            if haskey(tmp[day], "profit")
                day_profit += tmp[day]["profit"]
                bot_profits[JSON.parsefile(split(closed, "closed_orders")[1] * "config.json")["name"]] = tmp[day]["profit"]
            end
        end
    end

    msg = "Gestrige Zusammenfassung:
---
Profit: " * format(day_profit, precision=2) * " €
"
    for (k,v) in bot_profits
        msg *= "    " * k * ": " * format(v, precision=2) * " €
"
    end

    TelegramClient(ENV["telegram"]; chat_id=telegram_id)
    sendMessage(text = msg)
end
export send_daily_summary


function send_weekly_summary(user_id, telegram_id)
    day_profit = 0
    bot_profits = Dict()
    for n in 1:1:7
        day = string(today() - Day(n))
        yr,m,d = split(day, "-")
        closed_files = glob(joinpath(Pinguu.base_dir[2:end], "users/" * string(user_id) * "/*/closed_orders/" * yr * "/" * m * ".json"))
        for closed in closed_files
            tmp = JSON.parsefile(closed)
            if haskey(tmp, day)
                if haskey(tmp[day], "profit")
                    tmp_config = JSON.parsefile(split(closed, "closed_orders")[1] * "config.json")
                    if tmp_config["base_coin"] == "EUR"
                        day_profit += tmp[day]["profit"]
                        !haskey(bot_profits, tmp_config["name"]) ? bot_profits[tmp_config["name"]] = 0 : ""
                        bot_profits[tmp_config["name"]] += tmp[day]["profit"]
                    else
                        for (k,trade) in tmp[day]["trades"]
                            day_profit += trade["profit_EUR"]
                            !haskey(bot_profits, tmp_config["name"]) ? bot_profits[tmp_config["name"]] = 0 : ""
                            bot_profits[tmp_config["name"]] += trade["profit_EUR"]
                        end
                    end
                end
            end
        end
    end
    msg = "Wöchentliche Zusammenfassung:
---
Profit: " * format(day_profit, precision=2) * " €
"
    for (k,v) in bot_profits
        msg *= "    " * k * ": " * format(v, precision=2) * " €
"
    end

    TelegramClient(ENV["telegram"]; chat_id=telegram_id)
    sendMessage(text = msg)
end
export send_weekly_summary