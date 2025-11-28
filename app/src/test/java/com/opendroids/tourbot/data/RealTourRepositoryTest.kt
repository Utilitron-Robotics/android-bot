package com.opendroids.tourbot.data

import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.data.remote.model.RobotMessage
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.Ordering
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class RealTourRepositoryTest {

    private lateinit var robotClient: RobotClient
    private lateinit var tourRepository: RealTourRepository

    @Before
    fun setUp() {
        robotClient = mockk(relaxed = true)
        tourRepository = RealTourRepository(robotClient)
    }

    @Test
    fun `goTo sends correct command`() = runTest {
        val poi = "test_poi"
        tourRepository.goTo(poi)

        coVerify { robotClient.sendCommand(match { 
            it.op == "call_service" &&
            it.service == "/poi" &&
            it.id == "nav_$poi" &&
            it.args == mapOf("poi" to poi)
        }) }
    }

    @Test
    fun `cancelNavigation sends correct commands`() = runTest {
        tourRepository.cancelNavigation()

        coVerify(ordering = Ordering.SEQUENCE) { 
            robotClient.sendCommand(match { it.op == "advertise" && it.topic == "/move_base/cancel" })
            robotClient.sendCommand(match { it.op == "publish" && it.topic == "/move_base/cancel" })
            robotClient.sendCommand(match { it.op == "unadvertise" && it.topic == "/move_base/cancel" })
        }
    }

    @Test
    fun `observeStatus filters messages and returns status flow`() = runTest {
        val statusMessage = RobotStatusMessage(navStatus = 601, battery = 95f)
        val robotMessage = RobotMessage(topic = "/robot_status", msg = statusMessage)
        val messagesFlow = MutableStateFlow(robotMessage)

        coEvery { robotClient.messages } returns messagesFlow

        val result = tourRepository.observeStatus().first()

        // observeStatus() only filters messages, it doesn't send subscribe command
        // subscribeStatus() is a separate method that sends the subscribe command
        assertEquals(statusMessage, result)
    }

    @Test
    fun `subscribeStatus sends subscribe command`() = runTest {
        tourRepository.subscribeStatus()

        coVerify { robotClient.sendCommand(match {
            it.op == "subscribe" && it.topic == "/robot_status"
        }) }
    }

    @Test
    fun `unsubscribeStatus sends unsubscribe command`() = runTest {
        tourRepository.unsubscribeStatus()

        coVerify { robotClient.sendCommand(match {
            it.op == "unsubscribe" && it.topic == "/robot_status"
        }) }
    }
}
