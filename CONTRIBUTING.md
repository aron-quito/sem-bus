# Guía de Contribución y Convenciones de Ingeniería
## Proyecto Bus Conectado (BC) — Tacna, Perú

> **Estándar:** SWEBOK v4 / Gitflow Workflow & Conventional Commits  
> **Versión:** 1.0 (Noviembre 2026)

---

## 1. Política de Ramas (Gitflow)

El repositorio opera bajo el modelo **Gitflow** con ramas protegidas:

```
main          ─────────────────────────●──────────── (Producción estable / Releases)
                                      ▲
release/v1.0  ─────────────●──────────┘               (Preparación de lanzamiento)
                          ▲
develop       ─────●──────┴────────────●──────────── (Integración continua / Staging)
                  ▲                    ▲
feature/auth  ────┘                    │              (Nuevas funcionalidades)
hotfix/qr     ─────────────────────────┘              (Parches urgentes)
```

| Rama | Propósito | Reglas de Protección |
| :--- | :--- | :--- |
| `main` | Código en producción. Solo recibe merges desde `release/*` o `hotfix/*`. | Protegida. Requiere 2 revisiones y pipeline CI en verde. Prohibido push directo. |
| `develop` | Rama de integración continua. Despliega automáticamente a Staging. | Protegida. Requiere 1 revisión y tests pasando. |
| `feature/<nombre>` | Desarrollo de nuevos requerimientos (ej. `feature/otp-auth`, `feature/qr-scanner`). | Nace desde `develop`, se fusiona mediante Pull Request (PR) a `develop`. |
| `hotfix/<nombre>` | Correcciones críticas en producción (ej. `hotfix/negative-balance-race`). | Nace desde `main`, se fusiona a `main` y a `develop`. |

---

## 2. Convención de Mensajes de Commit (Conventional Commits)

Cada commit debe seguir el formato estándar:

```text
<tipo>(<alcance>): <descripción concisa en minúsculas y presente>

[cuerpo explicativo opcional]

[referencia a issue o caso de uso, ej: Closes #12, Ref CU-01]
```

### Tipos Permitidos
* `feat`: Nueva funcionalidad para el usuario (ej: `feat(auth): add otp sms verification flow`).
* `fix`: Corrección de un defecto o bug (ej: `fix(wallet): prevent race condition on concurrent debit`).
* `docs`: Cambios exclusivos en documentación o especificaciones (ej: `docs(api): update openapi spec for webhooks`).
* `test`: Adición o refactorización de pruebas unitarias o E2E (ej: `test(e2e): add maestro test for qr payment`).
* `refactor`: Modificación de código sin alterar comportamiento externo (ej: `refactor(db): optimize postgis spatial query`).
* `chore`: Mantenimiento de herramientas, dependencias o CI (ej: `chore(deps): bump fastapi to 0.110.1`).

---

## 3. Flujo de Trabajo para Pull Requests (PR)

1. Crear la rama local desde `develop` actualizado:
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b feature/nombre-de-la-tarea
   ```
2. Realizar los cambios respetando los estándares de código de cada lenguaje:
   * **Python:** Formateado con `black` y orden de imports con `isort`.
   * **iOS (Swift):** Cumplimiento con reglas de `SwiftLint`.
   * **Android (Kotlin):** Cumplimiento con `ktlint`.
3. Ejecutar las pruebas localmente:
   ```bash
   # Backend
   pytest --cov=app tests/
   ```
4. Subir la rama y abrir el Pull Request hacia `develop` utilizando la plantilla de PR.
5. El PR solo podrá fusionarse si:
   - Los pipelines de GitHub Actions finalizan en estado exitoso (verde).
   - La cobertura de pruebas no sufre degradación respecto a la línea base.
   - Cuenta con la aprobación formal del Lead Engineer o Reviewer asignado.

---

## 4. Entorno de Desarrollo Local Rápido

```bash
# 1. Clonar el repositorio
git clone https://github.com/aron-quito/sem-bus.git
cd sem-bus

# 2. Levantar Base de Datos y Cache en Docker
docker compose up -d postgres redis

# 3. Explorar el Mockup Interactivo en Navegador
open mockup/index.html
```

