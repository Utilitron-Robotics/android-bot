package com.utilitron.robotrelay.grpc

import com.utilitron.robotrelay.proto.RelayRequest
import com.utilitron.robotrelay.proto.RelayResponse
import com.utilitron.robotrelay.proto.RelayServiceGrpcKt

class RelayServiceImpl : RelayServiceGrpcKt.RelayServiceCoroutineImplBase() {
    override suspend fun relayMessage(request: RelayRequest): RelayResponse {
        println("Received message: ${request.message}")
        return RelayResponse.newBuilder().setMessage("Message received").build()
    }
}
