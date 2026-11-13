package pe.edu.unjbg.busconectado.pos

import org.junit.Assert.assertEquals
import org.junit.Test
import pe.edu.unjbg.busconectado.pos.data.PosCommissionCalculator

class PosCommissionTest {
    @Test
    fun `yape empresa flat fare 1_50 computes 2_95 percent commission and 1_46 net`() {
        val gross = PosCommissionCalculator.FLAT_FARE_PEN
        val commission = PosCommissionCalculator.yapeCommissionPen(gross)
        val net = PosCommissionCalculator.yapeNetPen(gross)
        assertEquals(0.04, commission, 0.001)
        assertEquals(1.46, net, 0.001)
    }

    @Test
    fun `app bus conectado has zero door commission`() {
        val gross = PosCommissionCalculator.FLAT_FARE_PEN
        assertEquals(1.50, PosCommissionCalculator.appDoorNetPen(gross), 0.001)
    }
}

