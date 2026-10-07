// SPDX-FileCopyrightText: Copyright (c) 2013-2021 Jeffrey Pfau
// SPDX-FileCopyrightText: Copyright 2026 Danilo / mGBAAndroid contributors
// SPDX-License-Identifier: MPL-2.0
package com.danilo.mgbaandroid;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Android-side port of the raw-save conversion rules used by mGBA 0.10.5's
 * Qt SaveConverter. This intentionally contains no emulator/runtime state so
 * conversion cannot affect gameplay, timing, audio, or the active save.
 */
final class SaveConverterUtil {
    private SaveConverterUtil() {}

    enum Endian { NONE, LITTLE, BIG }
    enum Kind {
        GBA_SRAM,
        GBA_FLASH512,
        GBA_FLASH1M,
        GBA_EEPROM,
        GBA_EEPROM512,
        GB_SRAM,
        GB_MBC2,
        GB_MBC6,
        GB_TAMA5
    }

    static final class InputFormat {
        final Kind kind;
        final Endian endian;
        final int size;
        final String label;

        InputFormat(Kind kind, Endian endian, int size, String label) {
            this.kind = kind;
            this.endian = endian;
            this.size = size;
            this.label = label;
        }

        List<Conversion> conversions(byte[] input) {
            if (input == null || input.length != size) return Collections.emptyList();
            List<Conversion> out = new ArrayList<>();
            switch (kind) {
                case GBA_EEPROM:
                case GBA_EEPROM512:
                    if (endian == Endian.LITTLE || endian == Endian.BIG) {
                        Endian target = endian == Endian.LITTLE ? Endian.BIG : Endian.LITTLE;
                        out.add(new Conversion(
                                "Trocar EEPROM para " + endianLabel(target),
                                "Inverte cada palavra de 64 bits, como o Save Converter oficial.",
                                swapGbaEepromEndian(input), ".sav"));
                    }
                    if (hasGbaRtc(size)) {
                        out.add(new Conversion(
                                "Remover dados RTC anexados",
                                "Remove os 16 bytes de RTC e mantém somente o save bruto.",
                                Arrays.copyOf(input, size & ~0xFF), ".sav"));
                    }
                    break;
                case GBA_SRAM:
                case GBA_FLASH512:
                case GBA_FLASH1M:
                    if (hasGbaRtc(size)) {
                        out.add(new Conversion(
                                "Remover dados RTC anexados",
                                "Remove os 16 bytes de RTC e mantém somente o save bruto.",
                                Arrays.copyOf(input, size & ~0xFF), ".sav"));
                    }
                    break;
                case GB_SRAM:
                    if ((size & 0xFF) != 0) {
                        out.add(new Conversion(
                                "Remover dados RTC anexados",
                                "Remove a área RTC anexada e mantém somente a SRAM.",
                                Arrays.copyOf(input, size & ~0xFF), ".sav"));
                    }
                    break;
                case GB_MBC2:
                    if (size == 0x100) {
                        Endian swapped = endian == Endian.LITTLE ? Endian.BIG : Endian.LITTLE;
                        out.add(new Conversion(
                                "MBC2 packed · " + endianLabel(swapped),
                                "Troca a ordem dos nibbles no formato MBC2 packed.",
                                swapMbc2Packed(input), ".sav"));
                        out.add(new Conversion(
                                "MBC2 unpacked · 512 bytes",
                                "Expande cada nibble para um byte MBC2, como no mGBA desktop.",
                                unpackMbc2(input, endian), ".sav"));
                    } else if (size == 0x200) {
                        out.add(new Conversion(
                                "MBC2 packed · little endian · 256 bytes",
                                "Compacta dois nibbles MBC2 por byte.",
                                packMbc2(input, Endian.LITTLE), ".sav"));
                        out.add(new Conversion(
                                "MBC2 packed · big endian · 256 bytes",
                                "Compacta dois nibbles MBC2 por byte.",
                                packMbc2(input, Endian.BIG), ".sav"));
                    }
                    break;
                case GB_MBC6:
                    if (size > GB_MBC6_FLASH) {
                        int sramSize = size - GB_MBC6_FLASH;
                        out.add(new Conversion(
                                "Extrair SRAM MBC6 · " + niceSize(sramSize),
                                "Extrai a parte SRAM do save combinado.",
                                Arrays.copyOfRange(input, 0, sramSize), ".sav"));
                        out.add(new Conversion(
                                "Extrair flash MBC6 · " + niceSize(GB_MBC6_FLASH),
                                "Extrai a parte flash do save combinado.",
                                Arrays.copyOfRange(input, sramSize, size), ".sav"));
                    }
                    break;
                case GB_TAMA5:
                default:
                    break;
            }
            return out;
        }
    }

    static final class Conversion {
        final String label;
        final String description;
        final byte[] data;
        final String extension;

        Conversion(String label, String description, byte[] data, String extension) {
            this.label = label;
            this.description = description;
            this.data = data;
            this.extension = extension;
        }
    }

    private static final int GBA_SRAM = 0x8000;
    private static final int GBA_FLASH512 = 0x10000;
    private static final int GBA_FLASH1M = 0x20000;
    private static final int GBA_EEPROM = 0x2000;
    private static final int GBA_EEPROM512 = 0x200;
    private static final int GB_MBC6_FLASH = 0x100000;

    static List<InputFormat> detect(byte[] data) {
        if (data == null) return Collections.emptyList();
        int n = data.length;
        List<InputFormat> result = new ArrayList<>();

        addGbaSimple(result, n, GBA_SRAM, Kind.GBA_SRAM, "GBA SRAM");
        addGbaSimple(result, n, GBA_FLASH512, Kind.GBA_FLASH512, "GBA Flash 64 KiB");
        addGbaSimple(result, n, GBA_FLASH1M, Kind.GBA_FLASH1M, "GBA Flash 128 KiB");
        if (n == GBA_EEPROM || n == GBA_EEPROM + 16) {
            addEepromCandidates(result, Kind.GBA_EEPROM, n, "GBA EEPROM 8 KiB");
        }
        if (n == GBA_EEPROM512 || n == GBA_EEPROM512 + 16) {
            addEepromCandidates(result, Kind.GBA_EEPROM512, n, "GBA EEPROM 512 B");
        }

        switch (n) {
            case 0x800:
            case 0x82C:
            case 0x830:
            case 0x2000:
            case 0x202C:
            case 0x2030:
            case 0x8000:
            case 0x802C:
            case 0x8030:
            case 0x10000:
            case 0x1002C:
            case 0x10030:
            case 0x20000:
            case 0x2002C:
            case 0x20030:
                result.add(new InputFormat(Kind.GB_SRAM, Endian.NONE, n,
                        "GB/GBC SRAM" + ((n & 0xFF) != 0 ? " + RTC" : "") + " · " + niceSize(n)));
                break;
            default:
                break;
        }

        if (n == 0x100) {
            result.add(new InputFormat(Kind.GB_MBC2, Endian.LITTLE, n, "GB/GBC MBC2 packed · little endian · 256 B"));
            result.add(new InputFormat(Kind.GB_MBC2, Endian.BIG, n, "GB/GBC MBC2 packed · big endian · 256 B"));
        } else if (n == 0x200) {
            result.add(new InputFormat(Kind.GB_MBC2, Endian.NONE, n, "GB/GBC MBC2 unpacked · 512 B"));
        }

        if (n == GB_MBC6_FLASH || n == GB_MBC6_FLASH + 0x8000) {
            result.add(new InputFormat(Kind.GB_MBC6, Endian.NONE, n,
                    n == GB_MBC6_FLASH ? "GB/GBC MBC6 flash · 1 MiB" : "GB/GBC MBC6 SRAM + flash · 1.03 MiB"));
        }
        if (n == 0x20) {
            result.add(new InputFormat(Kind.GB_TAMA5, Endian.NONE, n, "GB/GBC TAMA5 · 32 B"));
        }
        return result;
    }

    private static void addGbaSimple(List<InputFormat> out, int actual, int base, Kind kind, String name) {
        if (actual == base || actual == base + 16) {
            out.add(new InputFormat(kind, Endian.NONE, actual,
                    name + (actual == base + 16 ? " + RTC" : "") + " · " + niceSize(actual)));
        }
    }

    private static void addEepromCandidates(List<InputFormat> out, Kind kind, int n, String name) {
        String rtc = hasGbaRtc(n) ? " + RTC" : "";
        out.add(new InputFormat(kind, Endian.LITTLE, n, name + rtc + " · little endian"));
        out.add(new InputFormat(kind, Endian.BIG, n, name + rtc + " · big endian"));
    }

    private static boolean hasGbaRtc(int n) {
        return (n & 0xFF) == 0x10;
    }

    private static byte[] swapGbaEepromEndian(byte[] input) {
        byte[] out = new byte[input.length];
        int payload = input.length & ~0xFF;
        for (int i = 0; i + 7 < payload; i += 8) {
            for (int j = 0; j < 8; j++) out[i + j] = input[i + 7 - j];
        }
        // Match mGBA 0.10.5 SaveConverter: the endian operation only transforms
        // the aligned EEPROM payload. Preserve an RTC tail rather than silently
        // discarding user data; RTC stripping remains an explicit conversion.
        if (payload < input.length) {
            System.arraycopy(input, payload, out, payload, input.length - payload);
        }
        return out;
    }

    private static byte[] unpackMbc2(byte[] input, Endian endian) {
        byte[] out = new byte[0x200];
        int p = 0;
        for (byte value : input) {
            int b = value & 0xFF;
            int first = endian == Endian.BIG ? (b >> 4) & 0xF : b & 0xF;
            int second = endian == Endian.BIG ? b & 0xF : (b >> 4) & 0xF;
            out[p++] = (byte) (0xF0 | first);
            out[p++] = (byte) (0xF0 | second);
        }
        return out;
    }

    private static byte[] packMbc2(byte[] input, Endian endian) {
        byte[] out = new byte[0x100];
        for (int i = 0; i < out.length; i++) {
            int a = input[i * 2] & 0xF;
            int b = input[i * 2 + 1] & 0xF;
            out[i] = (byte) (endian == Endian.BIG ? ((a << 4) | b) : (a | (b << 4)));
        }
        return out;
    }

    private static byte[] swapMbc2Packed(byte[] input) {
        byte[] out = new byte[input.length];
        for (int i = 0; i < input.length; i++) {
            int b = input[i] & 0xFF;
            out[i] = (byte) (((b >>> 4) & 0xF) | ((b & 0xF) << 4));
        }
        return out;
    }

    static String niceSize(int bytes) {
        if (bytes >= 1024 * 1024 && bytes % (1024 * 1024) == 0) return (bytes / (1024 * 1024)) + " MiB";
        if (bytes >= 1024 && bytes % 1024 == 0) return (bytes / 1024) + " KiB";
        return bytes + " B";
    }

    private static String endianLabel(Endian endian) {
        return endian == Endian.BIG ? "big endian" : "little endian";
    }
}
