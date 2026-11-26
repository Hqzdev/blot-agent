package dev.blot.cloud.collaboration;

import dev.blot.application.ports.JsonCodec;
import java.util.*;
import org.springframework.web.util.HtmlUtils;

/** Public pages contain escaped content only; published JSON cannot introduce executable markup. */
public final class CloudPublicationRenderer {
  private final JsonCodec json;

  public CloudPublicationRenderer(JsonCodec json) {
    this.json = json;
  }

  public String render(CloudPublishedContent.Publication publication) {
    StringBuilder body =
        new StringBuilder("<h1>").append(escape(publication.title())).append("</h1>");
    Map<?, ?> value = json.read(publication.payload(), Map.class);
    if (publication.kind().equals("page") && value.get("blocks") instanceof List<?> blocks) {
      for (Object raw : blocks) {
        if (!(raw instanceof Map<?, ?> block)) continue;
        body.append("<section>");
        if (block.get("title") instanceof String title && !title.isBlank())
          body.append("<h2>").append(escape(title)).append("</h2>");
        if ("table".equals(block.get("kind"))
            && block.get("columns") instanceof List<?> columns
            && block.get("rows") instanceof List<?> rows) {
          body.append("<div class=table><table><thead><tr>");
          for (Object column : columns) body.append("<th>").append(escape(column)).append("</th>");
          body.append("</tr></thead><tbody>");
          for (Object rawRow : rows)
            if (rawRow instanceof List<?> row) {
              body.append("<tr>");
              for (Object cell : row) body.append("<td>").append(escape(cell)).append("</td>");
              body.append("</tr>");
            }
          body.append("</tbody></table></div>");
        } else body.append("<p>").append(escape(block.get("text"))).append("</p>");
        body.append("</section>");
      }
    } else {
      body.append("<section><p>")
          .append(escape(value.get("instructions")))
          .append("</p><h2>Tools</h2><p>")
          .append(escape(value.get("tools")))
          .append("</p></section>");
    }
    return "<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>"
        + escape(publication.title())
        + " · Ori</title><style>body{margin:0;background:#f8f8fa;color:#151515;font:17px system-ui}main{max-width:900px;margin:40px auto;padding:24px}section{background:white;border-radius:24px;padding:24px;margin:16px 0}h1{font-size:36px}h2{font-size:21px}p{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.6}.table{overflow:auto}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:12px;border-bottom:1px solid #eee}footer{color:#666;font-size:13px}</style><main>"
        + body
        + "<footer>Shared snapshot · Ori · Expires "
        + escape(publication.expiresAt())
        + "</footer></main></html>";
  }

  private static String escape(Object value) {
    return HtmlUtils.htmlEscape(value == null ? "" : value.toString());
  }
}
