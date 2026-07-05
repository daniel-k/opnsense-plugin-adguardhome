<?php

/*
 * Copyright (C) 2026
 * All rights reserved.
 */

namespace OPNsense\AdGuardHome\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\\OPNsense\\AdGuardHome\\General';
    protected static $internalServiceEnabled = 'enabled';
    protected static $internalServiceTemplate = 'OPNsense/AdGuardHome';
    protected static $internalServiceName = 'adguardhome';
}
