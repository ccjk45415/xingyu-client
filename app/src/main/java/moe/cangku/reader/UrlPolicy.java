package moe.cangku.reader;

import java.net.URI;

/** No credentials are sent outside the exact site origin. */
public final class UrlPolicy {
    public static final String ORIGIN = "https://cangku.moe";
    private UrlPolicy() {}
    public static boolean isSite(String value) {
        try {
            URI u = URI.create(value);
            return "https".equalsIgnoreCase(u.getScheme()) && "cangku.moe".equalsIgnoreCase(u.getHost())
                    && (u.getPort() == -1 || u.getPort() == 443) && u.getRawUserInfo() == null;
        } catch (Exception e) { return false; }
    }
    public static boolean isImage(String value) {
        try {
            URI u = URI.create(value);
            String host=u.getHost();
            return "https".equalsIgnoreCase(u.getScheme()) && host != null && u.getRawUserInfo() == null
                    && !host.equalsIgnoreCase("localhost") && !host.matches("[0-9.]+") && !host.contains(":");
        } catch (Exception e) { return false; }
    }
    public static boolean canOpen(String value) {
        try {
            URI u=URI.create(value.trim());
            String scheme=u.getScheme();
            return ("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))
                    ? u.getHost()!=null && u.getRawUserInfo()==null
                    : "magnet".equalsIgnoreCase(scheme) && value.startsWith("magnet:?");
        } catch (Exception e) { return false; }
    }
    public static long articleId(String value) {
        try {
            if (!isSite(value)) return 0;
            String path=URI.create(value).getPath();
            if (!path.matches("/archives/[0-9]+/?")) return 0;
            return Long.parseLong(path.split("/")[2]);
        } catch (Exception e) { return 0; }
    }
}
