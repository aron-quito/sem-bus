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

    @Test
    fun routeAutomationFindsTwoRouteTransferWhenNoSingleRouteConnects() {
        val stopA = TacnaDestinationPlace(
            id = "sA",
            name = "Alto de la Alianza",
            shortName = "Alto Alianza",
            subtitle = "Av. Jorge Basadre",
            latitude = -17.9950,
            longitude = -70.2450,
            routesPassing = listOf("Ruta 14")
        )
        val stopHub = TacnaDestinationPlace(
            id = "sHub",
            name = "Mercado Central",
            shortName = "Mercado Central",
            subtitle = "Av. Bolognesi",
            latitude = -18.01358,
            longitude = -70.25055,
            routesPassing = listOf("Ruta 14", "Ruta 10B")
        )
        val stopC = TacnaDestinationPlace(
            id = "sC",
            name = "Gregorio Albarracín",
            shortName = "Albarracín",
            subtitle = "Av. Municipal",
            latitude = -18.0400,
            longitude = -70.2380,
            routesPassing = listOf("Ruta 10B")
        )
        val ruta14 = TacnaOfficialRouteCatalogItem(
            id = "tacna-ruta-14",
            code = "RUTA 14",
            title = "Norte - Centro",
            routeType = "ordinary",
            isInService = true,
            keyStopIds = listOf("sA", "sHub")
        )
        val ruta10B = TacnaOfficialRouteCatalogItem(
            id = "tacna-ruta-10b",
            code = "RUTA 10B",
            title = "Centro - Sur",
            routeType = "ordinary",
            isInService = true,
            keyStopIds = listOf("sHub", "sC")
        )

        val origin = TacnaDestinationPlace.fromMapItem("Origen", "Norte", GeoPointData(-17.9952, -70.2451))
        val dest = TacnaDestinationPlace.fromMapItem("Destino", "Sur", GeoPointData(-18.0398, -70.2382))

        val result = RouteAutomationEngine.evaluateRoutes(
            origin = origin,
            destination = dest,
            stops = listOf(stopA, stopHub, stopC),
            routes = listOf(ruta14, ruta10B),
            activeBuses = emptyList()
        )

        val transfer = result.candidates.firstOrNull { it.isTransfer }
        assertTrue(transfer != null)
        assertEquals("RUTA 14 → RUTA 10B", transfer?.routeCode)
        assertEquals(EvaluatedCandidateKind.ORDINARY_IN_SERVICE, result.recommendedCandidate?.kind)
        assertTrue(result.recommendedCandidate?.isTransfer == true)
    }

    @Test
    fun routeAutomationRespectsForwardNodeOrderAndRejectsReverseDirection() {
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
            title = "Solo Ida Norte -> Sur",
            routeType = "ordinary",
            isInService = true,
            keyStopIds = listOf("s1", "s2")
        )

        // Intentar ir en sentido contrario (desde s2 hacia s1)
        val origin = TacnaDestinationPlace.fromMapItem("Origen", "UNJBG", GeoPointData(-18.0251, -70.2502))
        val dest = TacnaDestinationPlace.fromMapItem("Destino", "Centro", GeoPointData(-18.0136, -70.2506))

        val result = RouteAutomationEngine.evaluateRoutes(
            origin = origin,
            destination = dest,
            stops = listOf(stopA, stopB),
            routes = listOf(ruta14),
            activeBuses = emptyList()
        )

        assertTrue(result.candidates.none { it.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE })
        assertEquals(EvaluatedCandidateKind.WALKING_DIRECT, result.recommendedCandidate?.kind)
    }

    @Test
    fun routeAutomationRecommendsClosedLoopReboardOverLongWalkToTerminal() {
        val stopTerminal = TacnaDestinationPlace(
            id = "s-unjbgc1",
            name = "UNJBGC1",
            shortName = "UNJBGC1",
            subtitle = "Terminal",
            latitude = -18.0260,
            longitude = -70.2500,
            routesPassing = listOf("Ruta 14")
        )
        val stopCeid = TacnaDestinationPlace(
            id = "s-ceid",
            name = "Paradero Oficial CEID",
            shortName = "CEID",
            subtitle = "Av. Miraflores",
            latitude = -18.0200,
            longitude = -70.2490,
            routesPassing = listOf("Ruta 14")
        )
        val stopH2B = TacnaDestinationPlace(
            id = "s-h2b",
            name = "Paradero H2B",
            shortName = "H2B",
            subtitle = "Av. Cusco",
            latitude = -18.0080,
            longitude = -70.2420,
            routesPassing = listOf("Ruta 14")
        )
        val ruta14 = TacnaOfficialRouteCatalogItem(
            id = "tacna-ruta-14",
            code = "RUTA 14",
            title = "Circuito Cerrado",
            routeType = "ordinary",
            isInService = true,
            keyStopIds = listOf("s-unjbgc1", "s-ceid", "s-h2b"),
            isClosedLoop = true
        )

        val origin = TacnaDestinationPlace.fromMapItem("Origen", "Cerca H2B", GeoPointData(-18.0082, -70.2421))
        val dest = TacnaDestinationPlace.fromMapItem("Destino", "CEID", GeoPointData(-18.0201, -70.2491))

        val result = RouteAutomationEngine.evaluateRoutes(
            origin = origin,
            destination = dest,
            stops = listOf(stopTerminal, stopCeid, stopH2B),
            routes = listOf(ruta14),
            activeBuses = emptyList()
        )

        val rec = result.recommendedCandidate
        assertTrue(rec != null)
        assertTrue(rec?.isTransfer == true)
        assertEquals("RUTA 14 ↻ RUTA 14", rec?.routeCode)
        assertEquals("H2B", rec?.boardingPointName)
        assertEquals("CEID", rec?.alightingPointName)
    }

    @Test
    fun routeAutomationAllowsSingleBusAlightingAtClosedLoopTerminal() {
        val stopTerminal = TacnaDestinationPlace(
            id = "s-unjbgc1",
            name = "UNJBGC1",
            shortName = "UNJBGC1",
            subtitle = "Terminal",
            latitude = -18.0233,
            longitude = -70.2494,
            routesPassing = listOf("Ruta 14")
        )
        val stopPlazaVea = TacnaDestinationPlace(
            id = "s-pv",
            name = "Plaza Vea",
            shortName = "PV1",
            subtitle = "Av. Bolognesi",
            latitude = -18.0170,
            longitude = -70.2480,
            routesPassing = listOf("Ruta 14")
        )
        val stopH2B = TacnaDestinationPlace(
            id = "s-h2b",
            name = "Paradero H2B",
            shortName = "H2B",
            subtitle = "Av. Humboldt",
            latitude = -18.0400,
            longitude = -70.2420,
            routesPassing = listOf("Ruta 14")
        )
        val ruta14 = TacnaOfficialRouteCatalogItem(
            id = "tacna-ruta-14",
            code = "RUTA 14",
            title = "Circuito Cerrado",
            routeType = "ordinary",
            isInService = true,
            keyStopIds = listOf("s-unjbgc1", "s-pv", "s-h2b"),
            isClosedLoop = true
        )

        val origin = TacnaDestinationPlace.fromMapItem("Origen", "H2B", GeoPointData(-18.0401, -70.2421))
        val mercadoCentral = TacnaDestinationPlace.fromMapItem("Destino", "Mercado Central", GeoPointData(-18.0210, -70.2495))

        val result = RouteAutomationEngine.evaluateRoutes(
            origin = origin,
            destination = mercadoCentral,
            stops = listOf(stopTerminal, stopPlazaVea, stopH2B),
            routes = listOf(ruta14),
            activeBuses = emptyList()
        )

        val singleBus = result.candidates.firstOrNull { !it.isTransfer && it.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE }
        assertTrue(singleBus != null)
        assertEquals("H2B", singleBus?.boardingPointName)
        assertEquals("UNJBGC1", singleBus?.alightingPointName)
    }
}

