from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db
from app.models.transit import BusRoute, BusStop, Bus
from app.schemas.transit import (
    TransitNetworkResponse,
    BusRouteSchema,
    BusStopSchema,
    ActiveBusSchema,
)

router = APIRouter()


@router.get(
    "/network",
    response_model=TransitNetworkResponse,
    status_code=status.HTTP_200_OK,
    summary="Consultar rutas, paraderos y buses en operación (CU-07)",
    description="Devuelve las rutas, paraderos y buses activos desde la base de datos. Si aún no se han dado de alta paraderos ni unidades en turno, devuelve listas vacías para que el cliente renderice su estado limpio."
)
async def get_transit_network(
    db: AsyncSession = Depends(get_db)
):
    routes_stmt = (
        select(BusRoute)
        .where(BusRoute.is_active.is_(True))
        .options(selectinload(BusRoute.stops))
    )
    routes_res = await db.execute(routes_stmt)
    routes = routes_res.scalars().all()

    stops_stmt = (
        select(BusStop)
        .where(BusStop.is_active.is_(True))
        .order_by(BusStop.sequence_order)
    )
    stops_res = await db.execute(stops_stmt)
    stops = stops_res.scalars().all()

    buses_stmt = select(Bus).where(
        Bus.is_active.is_(True),
        Bus.is_visible_public.is_(True),
        Bus.gps_lat.is_not(None),
        Bus.gps_lng.is_not(None),
    )
    buses_res = await db.execute(buses_stmt)
    buses = buses_res.scalars().all()

    route_schemas = [
        BusRouteSchema(
            id=str(r.id),
            name=r.name,
            line_number=r.line_number,
            color_hex=r.color_hex,
            origin_name=r.origin_name,
            destination_name=r.destination_name,
            frequency_minutes=r.frequency_minutes,
            operating_hours=r.operating_hours,
            stops=[
                BusStopSchema(
                    id=str(s.id),
                    route_id=str(s.route_id),
                    name=s.name,
                    subtitle=s.subtitle,
                    latitude=s.latitude,
                    longitude=s.longitude,
                    sequence_order=s.sequence_order,
                    direction=s.direction,
                    is_key_stop=s.is_key_stop,
                )
                for s in r.stops
                if s.is_active
            ],
        )
        for r in routes
    ]

    stop_schemas = [
        BusStopSchema(
            id=str(s.id),
            route_id=str(s.route_id),
            name=s.name,
            subtitle=s.subtitle,
            latitude=s.latitude,
            longitude=s.longitude,
            sequence_order=s.sequence_order,
            direction=s.direction,
            is_key_stop=s.is_key_stop,
        )
        for s in stops
    ]

    bus_schemas = [
        ActiveBusSchema(
            id=str(b.id),
            route_id=str(b.route_id) if b.route_id else None,
            unit_number=b.unit_number,
            plate=b.plate,
            line_number="10",
            driver_name=b.driver_name,
            driver_rating=b.driver_rating,
            occupancy_current=b.occupancy_current,
            occupancy_max=b.occupancy_max,
            latitude=b.gps_lat or -18.0139,
            longitude=b.gps_lng or -70.2520,
            heading=b.gps_heading,
            speed_kmh=b.gps_speed,
            next_stop_name=b.next_stop_name,
            next_stop_eta_minutes=b.next_stop_eta_minutes,
        )
        for b in buses
    ]

    has_active = bool(route_schemas or stop_schemas or bus_schemas)

    return TransitNetworkResponse(
        routes=route_schemas,
        stops=stop_schemas,
        active_buses=bus_schemas,
        has_active_service=has_active,
        empty_reason="Sin paraderos ni unidades en ruta en este momento. Cuando se habiliten turnos y paraderos en el sistema, aparecerán automáticamente."
    )

