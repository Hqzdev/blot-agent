FROM eclipse-temurin:25-jdk AS build
WORKDIR /build
COPY backend/ ./
RUN ./gradlew --no-daemon :cloud:bootJar

FROM eclipse-temurin:25-jre
WORKDIR /app
RUN mkdir -p /app/data && chown -R 10001:10001 /app
COPY --from=build --chown=10001:10001 /build/cloud/build/libs/blot-cloud.jar /app/blot-cloud.jar
USER 10001:10001
ENV BLOT_CLOUD_ADDRESS=0.0.0.0 BLOT_CLOUD_PORT=8081 BLOT_CLOUD_DATABASE=/app/data/cloud.sqlite
EXPOSE 8081
ENTRYPOINT ["java", "--enable-native-access=ALL-UNNAMED", "-XX:MaxRAMPercentage=70", "-jar", "/app/blot-cloud.jar"]
