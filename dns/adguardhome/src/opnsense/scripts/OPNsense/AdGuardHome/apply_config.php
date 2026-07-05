#!/usr/local/bin/php
<?php

/*
 * Copyright (C) 2026
 * All rights reserved.
 *
 * Applies the plugin-managed settings (admin user/password, web port, DNS port)
 * to AdGuardHome.yaml:
 *
 *   - if the config file does not exist yet, a minimal config is seeded so
 *     AdGuard Home can start unprivileged (its first-launch check hard-requires
 *     root on FreeBSD, and is skipped once a config file exists);
 *   - if the config file already exists, ONLY the managed keys (http.address,
 *     dns.port, and — when a password is provided — the users block) are
 *     rewritten in place. Every other line is preserved byte-for-byte, so all
 *     settings AdGuard Home manages itself (filters, upstreams, clients, ...)
 *     are left untouched.
 *
 * AdGuard Home does not watch the file, so the caller restarts the service
 * afterwards for changes to take effect.
 */

require_once("script/load_phalcon.php");

use OPNsense\Core\Config;

$cfg = Config::getInstance()->object();
$agh = isset($cfg->OPNsense->AdGuardHome) ? $cfg->OPNsense->AdGuardHome : null;

function agh_val($node, $key, $default)
{
    if ($node !== null && isset($node->$key) && (string)$node->$key !== '') {
        return (string)$node->$key;
    }
    return $default;
}

$configpath = agh_val($agh, 'configpath', '/usr/local/etc/adguardhome/AdGuardHome.yaml');
$runas      = agh_val($agh, 'runas', 'adguardhome');
$setupuser  = agh_val($agh, 'setupuser', 'admin');
$setuppass  = ($agh !== null && isset($agh->setuppassword)) ? (string)$agh->setuppassword : '';
$webport    = agh_val($agh, 'webport', '3000');
$dnsport    = agh_val($agh, 'dnsport', '5353');

// Sanitize the user name (also masked in the model) to avoid YAML injection.
$setupuser = preg_replace('/[^A-Za-z0-9._-]/', '', $setupuser);
if ($setupuser === '') {
    $setupuser = 'admin';
}

// A password is only (re)written when one is provided; leaving the field blank
// keeps whatever is already in the config.
$new_users = null;
if ($setuppass !== '') {
    $hash = password_hash($setuppass, PASSWORD_BCRYPT);
    $new_users = "users:\n  - name: '{$setupuser}'\n    password: '{$hash}'";
}

if (!file_exists($configpath)) {
    // Fresh seed: minimal config; AdGuard Home fills in every other default.
    $users = ($new_users !== null) ? ($new_users . "\n") : "users: []\n";
    $yaml = "http:\n"
          . "  address: 0.0.0.0:{$webport}\n"
          . $users
          . "dns:\n"
          . "  bind_hosts:\n"
          . "    - 0.0.0.0\n"
          . "  port: {$dnsport}\n"
          . "  upstream_dns:\n"
          . "    - 127.0.0.1:53\n"
          . "  bootstrap_dns:\n"
          . "    - 127.0.0.1:53\n"
          . "schema_version: 34\n";

    $dir = dirname($configpath);
    if (!is_dir($dir)) {
        mkdir($dir, 0750, true);
    }
    if (file_put_contents($configpath, $yaml) === false) {
        fwrite(STDERR, "adguardhome: failed to seed config at {$configpath}\n");
        exit(1);
    }
    echo "adguardhome: seeded config at {$configpath}\n";
} else {
    // Surgical in-place update of only the managed keys.
    $lines = explode("\n", file_get_contents($configpath));
    $out = array();
    $section = null;
    $count = count($lines);
    for ($i = 0; $i < $count;) {
        $line = $lines[$i];
        // A top-level "key:" or "key: value" (column 0, not a list item).
        if (preg_match('/^([^\s:][^:]*):\s*(.*)$/', $line, $m)) {
            $key = $m[1];
            if ($key === 'users' && $new_users !== null) {
                $out[] = $new_users;
                $i++;
                // Skip the old (indented / list) users block.
                while ($i < $count && $lines[$i] !== '' &&
                       ($lines[$i][0] === ' ' || $lines[$i][0] === "\t" || $lines[$i][0] === '-')) {
                    $i++;
                }
                continue;
            }
            $section = $key;
            $out[] = $line;
            $i++;
            continue;
        }
        if ($section === 'http' && preg_match('/^  address: /', $line)) {
            $out[] = "  address: 0.0.0.0:{$webport}";
            $i++;
            continue;
        }
        if ($section === 'dns' && preg_match('/^  port: /', $line)) {
            $out[] = "  port: {$dnsport}";
            $i++;
            continue;
        }
        $out[] = $line;
        $i++;
    }
    if (file_put_contents($configpath, implode("\n", $out)) === false) {
        fwrite(STDERR, "adguardhome: failed to update config at {$configpath}\n");
        exit(1);
    }
    echo "adguardhome: updated managed keys in {$configpath}\n";
}

// Hand ownership to the run-as account (the rc script also chowns on start).
$pw = function_exists('posix_getpwnam') ? posix_getpwnam($runas) : false;
if ($pw !== false) {
    @chown($configpath, $runas);
    @chgrp($configpath, (int)$pw['gid']);
    $dir = dirname($configpath);
    @chown($dir, $runas);
    @chgrp($dir, (int)$pw['gid']);
}
@chmod($configpath, 0640);

exit(0);
