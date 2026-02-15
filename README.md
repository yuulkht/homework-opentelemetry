# ДЗ по Opentelemetry. Промышленное развертывание промышленных приложений. Дедлайн 18.02.26

## Выполнила Кухтина Юлия Егоровна, БПИ224

## Выполненные шаги

### 1. Запускаем миникуб и поднимаем все необходимые ресурсы в докере
Из корневой папки проекта
```
minikube start --cpus=4 --memory=6g  --driver=docker
docker compose up -d
```
### 1.1. Ресурсы в докере
docker-compose.yml
```
version: "3.0"
services:

  postgres:
    image: postgres
    ports:
      - 5432:5432
    environment:
      - POSTGRES_USER=muffin-wallet
      - POSTGRES_PASSWORD=muffin-wallet
      - POSTGRES_DB=muffin_wallet
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql

  postgres_exporter:
    image: quay.io/prometheuscommunity/postgres-exporter:latest
    container_name: postgres_exporter
    environment:
      DATA_SOURCE_NAME: "postgresql://muffin-wallet:muffin-wallet@localhost:5432/muffin_wallet?sslmode=disable"
    network_mode: host
    depends_on:
      - postgres

  prometheus:
    image: prom/prometheus:latest
    network_mode: host
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data_2:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.min-block-duration=120s'
      - '--storage.tsdb.max-block-duration=120s'
    restart: unless-stopped

  loki:
    image: grafana/loki:latest
    container_name: loki
    ports:
      - "3100:3100"
    volumes:
      - ./loki-config.yml:/etc/loki/loki-config.yaml
    command: -config.file=/etc/loki/loki-config.yaml


  grafana:
    ports:
      - "3000:3000"
    image: grafana/grafana:latest
    container_name: grafana
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    restart: unless-stopped

  zipkin:
    image: openzipkin/zipkin:latest
    container_name: zipkin
    ports:
      - "9411:9411"
    restart: unless-stopped

volumes:
  postgres_data:
  grafana-data:
  prometheus_data_2:
```
Изменения в конфигах локи и прометеуса, чтобы они воспринимали данные с коллектора:
```
auth_enabled: false

limits_config:
  allow_structured_metadata: true
  volume_enabled: true

server:
  http_listen_port: 3100

common:
  ring:
    instance_addr: 0.0.0.0
    kvstore:
      store: inmemory
  replication_factor: 1
  path_prefix: /tmp/loki

schema_config:
  configs:
    - from: 2020-05-15
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/index_cache
  filesystem:
    directory: /tmp/loki/chunks

pattern_ingester:
  enabled: true
```
```
global:
  scrape_interval: 10s

scrape_configs:
  - job_name: 'muffin-wallet'
    metrics_path: /metrics
    static_configs:
      - targets: ['wallet-collector.com']
        labels:
          application: 'muffin-wallet'

  - job_name: 'postgres'
    static_configs:
      - targets: [ 'localhost:9187' ]

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```

# 2 Устанавливаем cert-manager и Opentelemetry operator
```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml # тут нужно немного подождать, потому что поды должны успеть развернуться
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
```


### 2. Запускаем приложения
Переходим в папку `charts` и устанавливаем и разворачиваем приложение с истио с помощью хельмфайла
```
cd charts
helmfile sync
```
В отдельном терминале исполняем команду, чтобы получить доступ к приложению в браузере
```
minikube tunnel
```
### 3. Основные изменения для выполнения дз

#### 3.1. muffin-currency: добавляем в переменные окружения эндпоинт коллектора и меняем образ на актуальный
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: muffin-currency
  labels:
    app: muffin-currency
    app.kubernetes.io/name: muffin-currency
spec:
  replicas: 1
  selector:
    matchLabels:
      app: muffin-currency
  template:
    metadata:
      labels:
        app: muffin-currency
    spec:
      containers:
        - name: muffin-currency
          image: "aadan1lov/muffin-currency:1.2.0"
          imagePullPolicy: IfNotPresent
          env:
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: otel-collector-collector.default.svc.cluster.local:4317
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /rate?from=PLAIN&to=CHOKOLATE
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /rate?from=PLAIN&to=CHOKOLATE
              port: 8080
            initialDelaySeconds: 2
            periodSeconds: 5
```
#### 3.2. muffin-wallet: с помощью инит контейнера добавляем java-agent и конфигурируем через переменные окружения путь до коллектора
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: release-name-muffin-wallet
  labels:
    helm.sh/chart: muffin-wallet-0.1.0
    app.kubernetes.io/name: muffin-wallet
    app.kubernetes.io/instance: release-name
    app.kubernetes.io/version: "1.1.0"
    app.kubernetes.io/managed-by: Helm
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: muffin-wallet
      app.kubernetes.io/instance: release-name
  template:
    metadata:
      labels:
        app.kubernetes.io/name: muffin-wallet
        app.kubernetes.io/instance: release-name
    spec:

      volumes:
        - name: application-config-volume
          configMap:
            name: release-name-muffin-wallet
        - name: nginx-config-volume
          configMap:
            name: nginx-config
        - name: log-volume
          emptyDir: { }
        - name: agent-volume
          emptyDir: { }
      initContainers:
        - name: install-java-agent
          image: "yuulkht/java-agent:1.0.0"
          imagePullPolicy: Always
          command: [ 'sh', '-c', 'cp -r /opt/java-agent/. /shared-agents/' ]
          volumeMounts:
            - name: agent-volume
              mountPath: /shared-agents
      containers:
        - name: nginx-log
          image: nginx:1.29.3
          volumeMounts:
            - name: nginx-config-volume
              mountPath: /etc/nginx
            - name: log-volume
              mountPath: /usr/share/nginx/html

        - name: muffin-wallet
          image: "aadan1lov/muffin-wallet:1.2.0"
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 8081
              protocol: TCP
          volumeMounts:
            - name: application-config-volume
              mountPath: /app/config
            - name: log-volume
              mountPath: /logs
            - name: agent-volume
              mountPath: /shared-agents
          env:
            - name: JAVA_TOOL_OPTIONS
              value: "-javaagent:/shared-agents/opentelemetry-javaagent.jar"
            - name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
              value: "true"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://otel-collector-collector.default.svc.cluster.local:4318"
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "service.name=muffin-wallet"
          envFrom:
            - secretRef:
                name: release-name-muffin-wallet
            - configMapRef:
                name: release-name-muffin-wallet-env
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8081
            initialDelaySeconds: 90
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8081
            initialDelaySeconds: 80
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
```
#### 3.3. opentelemetry: добавляем ресурс для создания коллетктора с помощью оператора Opentelemetry, натсраиваем в нем эндпоинты на бэкенд-ресурсы обработчики, а также конфигурируем ингресс, с помощью которого прометеус в докере будет читать метрики с коллектора
```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: wallet-collector.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: otel-collector-collector
                port:
                  number: 8889
```
```
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch: {}

    exporters:
      zipkin:
        endpoint: http://host.minikube.internal:9411/api/v2/spans

      debug: {}

      prometheus:
        endpoint: "0.0.0.0:8889"
        const_labels:
          label1: muffin-wallet

      otlphttp/logs:
        endpoint: "http://host.minikube.internal:3100/otlp"
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [zipkin]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheus]
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlphttp/logs]
      telemetry:
        logs:
          level: "debug"
```


### 4. После запуска
#### 4.1. Swagger доступен по адресу http://muffin-wallet.com/swagger-ui/index.html
Он должен быть работоспособен и возвращать корректные коды ответа при выполнении HTTP-запросов, скрин:
![](screenshots/1.png)
#### 4.2. Логи приложения доступны на http://muffin-wallet-log.com/logs/app.log 
![](screenshots/2.png)

### 5. Используется графана по адресу http://localhost:3000/ с логином/паролем admin/admin
С помощью нее посмотрим на логи и метрики, дашборды и data sources подтягиваются из папки grafana
![](screenshots/8.png)
![](screenshots/9.png)
 ### 6. настройка трейсинга
После запуска просмотр трейсов доступен в Zipkin по адресу http://localhost:9411/zipkin (можно просто нажать на run query и посмотреть на последние трейсы)
![](screenshots/5.png)
![](screenshots/6.png)


### 7. Нагрузка

#### Для того, чтобы протестировать сбор метрик и дать небольшую нагрузку на приложение, был использован инструмент Jmeter. Для того, чтобы его использовать:

* Необходимо скачать с официального сайта архив https://jmeter.apache.org/download_jmeter.cgi
* Распаковать и добавить папку bin с исполняемыми файлами в path (если windows), можно ориентироваться на туториал https://habr.com/ru/articles/261483/
* В командной строке исполнить `jmeter.bat` и войти в GUI Jmeter, где можно удобно собрать скрипт для запуска
* В GUI по кнопке Open открыть скрипт из корня проекта `muffin-wallet.jmx`
* Скорректировать в HTTP-запросах данные, чтобы использовать id каких-то профилей, добавленных в базу заранее (ну или запросы просто попадут в неуспешные на графиках)
* Кнопкой Run запустить скрипт. Будет нагрузка на приложение в течение ~1.5 минут
