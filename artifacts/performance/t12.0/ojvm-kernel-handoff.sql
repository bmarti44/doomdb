whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off serveroutput on size unlimited feedback off timing off

create or replace and compile java source named doom_kernel_probe_src as
import java.io.ByteArrayOutputStream;
import java.sql.Blob;
import java.security.MessageDigest;
import java.util.zip.GZIPOutputStream;

public final class DoomKernelProbe {
  private static final int WIDTH = 320;
  private static final int HEIGHT = 200;
  private static final int SEGS = 2057;
  private static final double[] VX = new double[SEGS];
  private static final double[] VY = new double[SEGS];
  private static final double[] SX = new double[SEGS];
  private static final double[] SY = new double[SEGS];
  private static final byte[] FRAME = new byte[WIDTH * HEIGHT];

  static {
    int z = 0x13579bdf;
    for (int i = 0; i < SEGS; i++) {
      z ^= z << 13; z ^= z >>> 17; z ^= z << 5;
      VX[i] = (z & 4095) - 1024;
      z = z * 1664525 + 1013904223;
      VY[i] = (z & 4095) - 1024;
      z = z * 1664525 + 1013904223;
      SX[i] = ((z & 511) - 255) + 0.25;
      z = z * 1664525 + 1013904223;
      SY[i] = ((z & 511) - 255) + 0.25;
    }
  }

  private static byte[] frame(int seed) throws Exception {
    int noise = seed ^ 0x6d2b79f5;
    for (int x = 0; x < WIDTH; x++) {
      double angle = ((x - 159.5) / 320.0) * 1.5707963267948966;
      double rx = Math.cos(angle), ry = Math.sin(angle);
      double nearest = Double.POSITIVE_INFINITY;
      int nearestSeg = 0;
      for (int i = 0; i < SEGS; i++) {
        double den = rx * SY[i] - ry * SX[i];
        if (den == 0.0) continue;
        double t = (VX[i] * SY[i] - VY[i] * SX[i]) / den;
        double u = (VX[i] * ry - VY[i] * rx) / den;
        if (t > 0.0001 && u >= 0.0 && u <= 1.0 && t < nearest) {
          nearest = t; nearestSeg = i;
        }
      }
      int horizon = 100 + (int)(20.0 * Math.sin(x * 0.03125 + seed));
      for (int y = 0; y < HEIGHT; y++) {
        noise ^= noise << 13; noise ^= noise >>> 17; noise ^= noise << 5;
        int texture = nearestSeg * 31 + x * 7 + y * 13 + (noise >>> 24);
        int light = y < horizon ? 224 : 128;
        FRAME[x * HEIGHT + y] = (byte)((texture ^ light) & 255);
      }
    }
    for (int y = 164; y < 200; y++) {
      for (int x = 104; x < 216; x++) {
        FRAME[x * HEIGHT + y] = (byte)((x * 3 + y * 5 + seed) & 255);
      }
    }

    MessageDigest sha = MessageDigest.getInstance("SHA-256");
    byte[] digest = sha.digest(FRAME);
    StringBuilder json = new StringBuilder(700000);
    json.append("{\"v\":1,\"frame_sha\":\"");
    for (byte b : digest) {
      int v = b & 255;
      if (v < 16) json.append('0');
      json.append(Integer.toHexString(v));
    }
    json.append("\",\"runs\":[");
    boolean comma = false;
    for (int x = 0; x < WIDTH; x++) {
      int start = 0;
      int color = FRAME[x * HEIGHT] & 255;
      for (int y = 1; y <= HEIGHT; y++) {
        int next = y == HEIGHT ? -1 : FRAME[x * HEIGHT + y] & 255;
        if (next != color) {
          if (comma) json.append(',');
          comma = true;
          json.append('[').append(x).append(',').append(start).append(',')
              .append(y - start).append(',').append(color).append(']');
          start = y; color = next;
        }
      }
    }
    json.append("]}");
    ByteArrayOutputStream bytes = new ByteArrayOutputStream(160000);
    GZIPOutputStream gzip = new GZIPOutputStream(bytes);
    gzip.write(json.toString().getBytes("UTF-8"));
    gzip.finish(); gzip.close();
    return bytes.toByteArray();
  }

  public static void fill(int seed, Blob payload) throws Exception {
    byte[] bytes = frame(seed);
    payload.truncate(0);
    payload.setBytes(1, bytes);
  }
}
/

create or replace procedure doom_kernel_probe_fill(
  p_seed in number,p_payload in blob
) as language java
name 'DoomKernelProbe.fill(int, java.sql.Blob)';
/

declare
  type num_tab is table of number index by binary_integer;
  l_ms num_tab;
  l_payload blob;
  l_t0 timestamp;
  l_tmp number;
  l_n constant pls_integer:=30;
  function elapsed_ms(p_start timestamp) return number is
    x interval day to second:=systimestamp-p_start;
  begin
    return extract(day from x)*86400000+extract(hour from x)*3600000+
      extract(minute from x)*60000+extract(second from x)*1000;
  end;
begin
  dbms_lob.createtemporary(l_payload,true,dbms_lob.call);
  for i in 1..10 loop doom_kernel_probe_fill(-i,l_payload); end loop;
  for i in 1..l_n loop
    l_t0:=systimestamp;
    doom_kernel_probe_fill(i,l_payload);
    l_ms(i):=elapsed_ms(l_t0);
  end loop;
  for i in 1..l_n-1 loop
    for j in i+1..l_n loop
      if l_ms(j)<l_ms(i) then
        l_tmp:=l_ms(i);l_ms(i):=l_ms(j);l_ms(j):=l_tmp;
      end if;
    end loop;
  end loop;
  dbms_output.put_line('KERNEL_SAMPLES='||l_n);
  dbms_output.put_line('KERNEL_PAYLOAD_BYTES='||dbms_lob.getlength(l_payload));
  dbms_output.put_line('KERNEL_P50_MS='||to_char(l_ms(ceil(l_n*.50)),'FM9999990.000'));
  dbms_output.put_line('KERNEL_P95_MS='||to_char(l_ms(ceil(l_n*.95)),'FM9999990.000'));
  dbms_output.put_line('KERNEL_P99_MS='||to_char(l_ms(ceil(l_n*.99)),'FM9999990.000'));
  dbms_output.put_line('KERNEL_MAX_MS='||to_char(l_ms(l_n),'FM9999990.000'));
  dbms_lob.freetemporary(l_payload);
end;
/

select name,method_name,is_compiled from user_java_methods
where name='DoomKernelProbe' order by method_name;

drop procedure doom_kernel_probe_fill;
drop java source doom_kernel_probe_src;

select count(*) as kernel_probe_objects from user_objects
where upper(object_name) like '%DOOM%KERNEL%PROBE%';
select count(*) as invalid_objects from user_objects where status<>'VALID';
