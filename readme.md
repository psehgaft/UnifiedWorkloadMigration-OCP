# OpenShift S2I deployment from a local directory (Java / PHP / Ruby)

This guide matches the included Jupyter notebook: **openshift_s2i_local_source_deployer.ipynb**.

## What you are doing

OpenShift S2I normally builds from a Git URL, e.g. `oc new-app <builder>~https://git/...`.  
When your source is local, use a **Binary** BuildConfig and upload the directory with:

- `oc start-build <bc-name> --from-dir=<local_dir> --follow`

## Recommended builders

Use cluster-provided ImageStreamTags (preferred):
- Java: `openjdk:17`
- PHP: `php:8.2`
- Ruby: `ruby:3.1`

Fallback pullspecs (public UBI-based images):
- Java: `registry.access.redhat.com/ubi9/openjdk-17`
- PHP: `registry.access.redhat.com/ubi9/php-82`
- Ruby: `registry.access.redhat.com/ubi9/ruby-31`

## Step-by-step (CLI)

### 1) Select a namespace

```bash
export NS=s2i-demo
oc new-project $NS || true
oc project $NS
```

### 2) Create a binary S2I BuildConfig

```bash
export APP=myapp
export BUILDER=openjdk:17   # or php:8.2 or ruby:3.1
# fallback: export BUILDER=registry.access.redhat.com/ubi9/openjdk-17
oc new-build --name $APP --binary=true --strategy=source $BUILDER
```

### 3) Start the build from your local source directory

```bash
export SRC=/absolute/path/to/your/app
oc start-build $APP --from-dir="$SRC" --follow
```

### 4) Deploy from the resulting image

```bash
oc new-app --image-stream $APP:latest --name $APP
oc expose svc/$APP     # creates a Route (optional)
```

### 5) Verify

```bash
oc get pods
oc get svc
oc get route $APP
```

## `.s2i/environment` quick recipes

You can create a `.s2i/environment` file in your repo to pass S2I-time variables.

### PHP example
```bash
mkdir -p .s2i
cat > .s2i/environment <<'EOF'
DOCUMENTROOT=/public
PHP_MEMORY_LIMIT=256M
EOF
```

### Ruby example
```bash
mkdir -p .s2i
cat > .s2i/environment <<'EOF'
RACK_ENV=production
PUMA_MAX_THREADS=16
EOF
```

### Java example
```bash
mkdir -p .s2i
cat > .s2i/environment <<'EOF'
MAVEN_ARGS_APPEND=-DskipTests
JAVA_MAX_MEM_RATIO=80
EOF
```

---

## References (APA)

Red Hat. (2026). *Builds using BuildConfig* (OpenShift Container Platform documentation). Red Hat. https://docs.redhat.com/

OKD Documentation Project. (2026). *Performing and configuring basic builds (Starting a build with --from-dir)*. OKD Documentation. https://docs.okd.io/

OpenShift Cookbook. (2026). *How can I build from local source instead of a Git repository?* OpenShift Cookbook. https://cookbook.openshift.org/

Red Hat. (2026). *OpenJDK 17 (ubi9/openjdk-17) container image* (Red Hat Ecosystem Catalog). Red Hat. https://catalog.redhat.com/

Red Hat. (2026). *Apache 2.4 with PHP 82 (ubi9/php-82) container image* (Red Hat Ecosystem Catalog). Red Hat. https://catalog.redhat.com/

Red Hat. (2026). *Ruby 3.1 (ubi9/ruby-31) container image* (Red Hat Ecosystem Catalog). Red Hat. https://catalog.redhat.com/

Red Hat. (2025). *Red Hat UBI OpenJDK container images* (environment variables). Red Hat OpenJDK team. https://rh-openjdk.github.io/redhat-openjdk-containers/
