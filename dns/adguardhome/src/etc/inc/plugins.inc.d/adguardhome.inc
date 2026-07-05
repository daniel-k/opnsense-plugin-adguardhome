<?php

/*
 * Copyright (C) 2026
 * All rights reserved.
 */

function adguardhome_services()
{
    $services = array();
    $mdlGeneral = new \OPNsense\AdGuardHome\General();

    if ($mdlGeneral->enabled->__toString() == "0") {
        return $services;
    }

    $services[] = array(
        'description' => gettext('AdGuard Home'),
        'configd' => array(
            'restart' => array('adguardhome restart'),
            'start' => array('adguardhome start'),
            'stop' => array('adguardhome stop'),
            'status' => array('adguardhome status'),
        ),
        'name' => 'adguardhome',
        'pidfile' => '/var/run/adguardhome.pid'
    );

    return $services;
}
