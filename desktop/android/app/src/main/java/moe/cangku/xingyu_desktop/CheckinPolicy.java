package moe.cangku.xingyu_desktop;

import java.time.Instant;
import java.time.ZoneOffset;

/** Pure policy shared by the native scheduler and isolated JVM checks. */
final class CheckinPolicy {
    static final int PERIODIC_JOB = 73104, INITIAL_JOB = 73106, VERSION = 2;
    static final long PERIOD = 15 * 60 * 1000L, FLEX = 5 * 60 * 1000L, BACKOFF = 60 * 1000L;
    enum Outcome { SIGNED, TRANSIENT, LOGIN, STOPPED }
    static boolean retry(Outcome outcome, int failures) {
        return outcome == Outcome.TRANSIENT && failures > 0 && failures <= 3;
    }
    static boolean today(String timestamp, Instant now) {
        try { return Instant.parse(timestamp).atOffset(ZoneOffset.ofHours(8)).toLocalDate()
                .equals(now.atOffset(ZoneOffset.ofHours(8)).toLocalDate()); }
        catch (RuntimeException ignored) { return false; }
    }
}
