<p>
  <a href="http://opencms.org/" alt="OpenCms">
    <img src="https://www.alkacon.com/export/shared/web/logos/opencms-logo.svg" alt="OpenCms logo" width="340" height="84">
  </a>
</p>

# OpenCms Docker Image (SAGA fork)

Tomcat-based Docker image for [OpenCms](http://opencms.org/), maintained by SAGA Soluciones as a fork of the [official Alkacon image](https://github.com/alkacon/opencms-docker).

This fork publishes a unified `image/` build context driven by [`versions.yaml`](./versions.yaml), supporting OpenCms 19.0 → 21.0.1 on `tomcat:9.0-jdk21` and legacy OpenCms 10.5.4 on `tomcat:8.5-jdk8`.

## Available tags

Published as `sagasoluciones/opencms-tomcat:<tag>` on Docker Hub. Source of truth: [`versions.yaml`](./versions.yaml).

| Tag | OpenCms | Base image | Notes |
|---|---|---|---|
| `latest`, `21.0.1` | 21.0.1 | `tomcat:9.0-jdk21` | |
| `20.0` | 20.0 | `tomcat:9.0-jdk21` | |
| `19.0` | 19.0 | `tomcat:9.0-jdk21` | |
| `10.5.4` | 10.5.4 | `tomcat:8.5-jdk8` | legacy; see section below |

For OpenCms versions older than 10.5.4, see the original [`pre_11_images`](https://github.com/alkacon/opencms-docker/blob/pre_11_images/README.md) branch of the upstream repo.

## How to use this image

### Step 1: docker-compose.yml

Save the following *docker-compose.yml* file to your host machine.

```
services:
    mariadb:
        image: mariadb:latest
        container_name: mariadb
        init: true
        restart: always
        volumes:
            - ~/dockermount/opencms-docker-mysql:/var/lib/mysql
        environment:
            - "MYSQL_ROOT_PASSWORD=secretDBpassword"
    opencms:
        image: sagasoluciones/opencms-tomcat:21.0.1
        container_name: opencms
        init: true
        restart: always
        depends_on: [ "mariadb" ]
        links:
            - "mariadb:mysql"
        ports:
            - "80:8080"
        volumes:
            - ~/dockermount/opencms-docker-webapps:/container/webapps
        command: ["/root/wait-for.sh", "mysql:3306", "-t", "30", "--", "/root/opencms-run.sh"]
        environment:
             - "DB_PASSWD=secretDBpassword"
```

Change the MariaDB root password `secretDBpassword`.

### Step 2: Persist data

Adjust the following directories for your host system:

* `~/dockermount/opencms-docker-mysql` the directory where all MariaDB data are persisted
* `~/dockermount/opencms-docker-webapps` the Tomcat webapps directory that contains important configurations, caches and indices of OpenCms

Configured in this way, it is possible to upgrade the `opencms` and `mariadb` containers while keeping all your OpenCms and MariaDB data. See the upgrade guide below.

On the other hand, if you like to start with a completely fresh OpenCms installation, do not forget to delete both mounted directories before.

### Step 3: Start OpenCms and MariaDB

Navigate to the folder with the *docker-compose.yml* file and execute `docker-compose up -d`.

Startup will take a while since numerous modules are installed.

You can follow the installation process with `docker-compose logs -f opencms`.

### Step 4: Login to OpenCms

When the containers are set up, you can access the OpenCms workplace via `http://localhost/system/login`.

The default account is username `Admin` with password `admin`.

## Environment variables

In addition to `DB_PASSWD`, the following environment variables are supported:

* `DB_HOST`, the database host name, defaults to `mysql`
* `DB_USER`, the database user, default is `root`
* `DB_PASSWD`, the database password, is not set by default
* `DB_PASSWD_FILE`, file in the container where the database password is stored (`/run/secrets/<secret_name>`); to be used with docker compose `secrets`
* `DB_NAME`, the database name, default is `opencms`
* `ADMIN_PASSWD`, the admin password, defaults to `admin`
* `ADMIN_PASSWD_FILE`, file in the container where the admin password is stored (`/run/secrets/<secret_name>`); to be used with docker compose `secrets`
* `OPENCMS_COMPONENTS`, the OpenCms components to install, default is `workplace,demo`; to not install the demo template use `workplace`
* `JETTY_OPTS`, the Jetty startup options (in addition to predefined options), default is `-Xmx2g`
* `DEBUG`, flag indicating whether to enable verbose debug logging and allowing connections via {docker ip address}:8000, defaults to `false`
* `JSONAPI`, flag indicating whether to enable the JSON API, default is `false`
* `SERVER_URL`, the server URL, default is `http://localhost`

The variables `DB_PASSWD` and `DB_PASSWD_FILE` respectively `ADMIN_PASSWD` and `ADMIN_PASSWD_FILE` are alternatives. Read more about docker compose secrets [here](https://docs.docker.com/compose/how-tos/use-secrets/).

## Upgrade the image

*Before upgrading the image, make sure that you have persisted your OpenCms data and MariaDB data with Docker volumes as described above. Otherwise you will lose your data.*

Enter the target version of the OpenCms image in your docker-compose.yml file.

```
    opencms:
        image: sagasoluciones/opencms-tomcat:21.0.1
```

Navigate to the folder with the docker-compose.yml file and execute `docker-compose up -d`.

During startup, the Docker setup will update several modules as well as JAR files and configurations in the `/container/webapps` directory.

You can follow the installation process with `docker compose logs -f opencms`.

*It is recommended to remove the* `/container/webapps/ROOT/WEB-INF/index` *folder after upgrade and do a full Solr reindex.*

## Support for other databases

OpenCms uses a special configuration file called [setup.properties](https://github.com/alkacon/opencms-core/blob/master/src-setup/org/opencms/setup/setup.properties.example) to establish a database connection.

In order to connect to a database other than MariaDB, this image supports connection via a custom *setup.properties* file.

The file must be named `custom-setup.properties` and must be available in the root folder of the docker container.

An example setup for PostgreSQL can be found [here](https://github.com/alkacon/opencms-docker/tree/master/compose/postgres).

For more information on the DB configuration options, see the [OpenCms documentation](https://documentation.opencms.org/opencms-documentation/server-administration/headless-installation/).

Note: when using a custom configuration file, the environment variables `DB_HOST, DB_USER, DB_PASSWD, DB_NAME, OPENCMS_COMPONENTS, SERVER_URL` are ignored.

## Building the image

Published images are available on Docker Hub (`sagasoluciones/opencms-tomcat:<tag>`). To build locally:

```bash
# Requires yq + jq on PATH
./scripts/build.sh 21.0.1       # builds sagasoluciones/opencms-tomcat:21.0.1-dev
./scripts/build.sh 10.5.4       # builds the legacy OpenCms 10.5.4 image
```

`scripts/build.sh` reads [`versions.yaml`](./versions.yaml) and passes the correct base image, OpenCms distribution URL, SHA256 digest and `OPENCMS_VERSION` to the Docker build. The `-dev` suffix marks images as local only — Docker Hub publication happens via the `<version>-tomcat` git tag (see [`.github/workflows/publish.yml`](./.github/workflows/publish.yml)).

The top-level `docker-compose.yml` is provided as a quick-start example for OpenCms 21.0.1 against MariaDB. For version-pinned compose stacks, see [`compose/<version>/`](./compose/).

## OpenCms 10.5.4 (Legacy)

### What's included

All features of the unified image apply:
- Runtime setup via `CmsAutoSetup` against an external MariaDB or PostgreSQL database
- XSLT configuration pipeline (locale, timezone, mail, server URL)
- Hash-tracked project-config drop-in overrides (`/opt/opencms-project-config/`)
- Optional module zip seeding at first boot (`/opt/opencms-modules/*.zip`)
- Secrets via `*_FILE` env vars (`ADMIN_PASSWD_FILE`, `DB_PASSWD_FILE`)
- gosu privilege drop (runs as `opencms` user uid 998)

### Differences from OpenCms 19+

| | 10.5.4 | 19 / 20 / 21 |
|---|---|---|
| Java | 8 (JDK 8) | 21 |
| Tomcat | 8.5 | 9.0 |
| Apollo / Mercury templates | Not included | Not applicable (19+) |
| JSONAPI module | Not available | Optional via `JSONAPI=true` env |
| Default components | `workplace` | `workplace,demo` |
| Root URL (`/`) | 404 until a site is created | Demo site (if components include `demo`) |
| Module templates | Classic OpenCms workplace template | — |

### Quick start

```bash
# Build the image (requires yq + jq)
./scripts/build.sh 10.5.4

# Start with MariaDB
docker compose -f compose/10.5.4/docker-compose.yml up
```

Workplace is available at `http://localhost/opencms/system/login` (default password: `admin`).

### Git integration

To use the Alkacon `module-checkin` git workflow (same as UPO/IBJOVE projects):
1. Copy the `init-env.sh` template from an existing project (e.g., `IBJOVE-Web-Reservas`)
2. Set `OPENCMS_VERSION=10.5.4` in the generated `.env`
3. Mount your repo and `~/.ssh` as documented in that project's `README.md`

OpenCms 10.5.4 ships `WEB-INF/git-scripts/` (module `org.opencms.module.git` introduced in 10.5.0).

### Known limitations
- `tomcat:8.5-jdk8` is an archived image (Tomcat 8.5 EOL 2024-03-31). Pin to a specific digest for long-term reproducibility.
- After fresh install with `OPENCMS_COMPONENTS=workplace`, `http://localhost/` returns 404 — create a site via Workplace → Administration → Sites.
- No upgrade path from 10.5.4 to 11+ within this image; treat them as separate installations.

## License

View the [licence information on GitHub](https://github.com/alkacon/opencms-docker/blob/master/LICENSE).
