function cancel_invest(invest, client, invest_path)
    if !haskey(invest, "order")
        rm(invest_path)
        return
    end
    order = client.get_order(orderId=invest["order"]["orderId"], symbol=invest["symbol"])
    @info("Test 1")
    
    if !(order["status"] in [client.ORDER_STATUS_CANCELED, client.ORDER_STATUS_FILLED])
        result = client.cancel_order(
            symbol=invest["symbol"],
            orderId=invest["order"]["orderId"])
        @info("Status 1: " * order["status"])
        if result !== nothing
            if parse(Float64, result["executedQty"]) == 0.0 && result["status"] == client.ORDER_STATUS_CANCELED
                rm(invest_path)
            else
                Pinguu.move_to_filled(invest, result, client, invest_path)
            end
        end
    else
        @info("Status 2: " * order["status"])
        if parse(Float64, order["executedQty"]) == 0.0 && order["status"] == client.ORDER_STATUS_CANCELED
            rm(invest_path, force=true)
        else
            @info("Order FILLED")
            Pinguu.move_to_filled(invest, order, client, invest_path)
        end
    end
end
export cancel_invest