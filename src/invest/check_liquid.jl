function check_liquid(client, invest)
    account = client.get_account()
    for b in account["balances"]
        if b["asset"] == invest["symbol"][end-2:end]
            if parse(Float64, b["free"]) > parse(Float64, invest["amount"])
                return true
            else
                return false
            end
        end
    end
    return false
end
export check_liquid