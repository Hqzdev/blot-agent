package dev.blot.cloud;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/** Separate process: does not scan or start the legacy desktop API or its agent workers. */
@SpringBootApplication
@EnableScheduling
public class CloudServer {
  public static void main(String[] args) {
    var application = new SpringApplication(CloudServer.class);
    var defaults = new java.util.HashMap<String, Object>();
    defaults.putAll(CloudRuntimeEnvironment.load(System.getenv()));
    application.setDefaultProperties(defaults);
    application.run(args);
  }
}
