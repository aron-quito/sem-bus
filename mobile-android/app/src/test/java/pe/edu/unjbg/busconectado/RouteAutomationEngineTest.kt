package pe.edu.unjbg.busconectado

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import pe.edu.unjbg.busconectado.core.location.GeoPointData
import pe.edu.unjbg.busconectado.core.location.LocationService
import pe.edu.unjbg.busconectado.core.model.EvaluatedCandidateKind
import pe.edu.unjbg.busconectado.core.model.RouteAutomationEngine
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.core.model.TacnaOfficialRouteCatalogItem
import pe.edu.unjbg.busconectado.core.model.UserRoleType

class RouteAutomationEngineTest {

    @Test
    fun roleFaresMatchSpecification() {
        assertEquals(15, UserRoleType.ADULT.farePoints)
        assertEquals(7, UserRoleType.STUDENT.farePoints)
        assertEquals(0, UserRoleType.CONADIS.farePoints)
    }

    @Test
    fun sanitizeOutOfBoundsLocationFallsBackToTacna() {
        val outOfPeru = GeoPointData(37.7749, -122.4194)
        val safe = LocationService.sanitizedTacnaCoordinate(outOfPeru)
        assertTrue(LocationService.isWithinTacna(safe))
        assertEquals(LocationService.TACNA_DEFAULT, safe)
    }

    @Test
    fun routeAutomationRecommendsOrdinaryRouteWhenInService() {
        val stopA = TacnaDestinationPlace(
            id = "s1",
            name = "Mercado Central",
            shortName = "Mercado Central",
            subtitle = "Av. Bolognesi",
            latitude = -18.01358,
            longitude = -70.25055,
            routesPassing = listOf("Ruta 14")
        )
        val stopB = TacnaDestinationPlace(
            id = "s2",
            name = "UNJBG Campus",
            shortName = "UNJBG",
            subtitle = "Av. Miraflores",
            latitude = -18.0252,
            longitude = -70.2503,
            routesPassing = listOf("Ruta 14")
        )
        val ruta14 = TacnaOfficialRouteCatalogItem(
            id = "tacna-ruta-14",
            code = "RUTA 14",
            title = "Eje Troncal",
            routeType = "ordinary",
            isInService = true,
            keyStopIds = listOf("s1", "s2")
        )

        val origin = TacnaDestinationPlace.fromMapItem("Origen", "Centro", GeoPointData(-18.0136, -70.2506))
        val dest = TacnaDestinationPlace.fromMapItem("Destino", "UNJBG", GeoPointData(-18.0251, -70.2502))

        val result = RouteAutomationEngine.evaluateRoutes(
            origin = origin,
            destination = dest,
            stops = listOf(stopA, stopB),
            routes = listOf(ruta14),
            activeBuses = emptyList()
        )

        assertTrue(result.hasOrdinaryInService)
        assertEquals(EvaluatedCandidateKind.ORDINARY_IN_SERVICE, result.recommendedCandidate?.kind)
        assertEquals("RUTA 14", result.recommendedCandidate?.routeCode)
    }
}

