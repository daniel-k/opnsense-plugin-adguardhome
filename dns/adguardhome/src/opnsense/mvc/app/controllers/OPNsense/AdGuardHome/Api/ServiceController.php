<?php

/*
 * Copyright (C) 2026
 * All rights reserved.
 */

namespace OPNsense\AdGuardHome\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\\OPNsense\\AdGuardHome\\General';
    protected static $internalServiceEnabled = 'enabled';
    protected static $internalServiceTemplate = 'OPNsense/AdGuardHome';
    protected static $internalServiceName = 'adguardhome';

    /**
     * Apply the plugin-managed settings (admin user/password, web port, DNS
     * port) to AdGuardHome.yaml before regenerating templates and (re)starting
     * the service. This seeds a minimal config on first run, and afterwards only
     * rewrites those managed keys in place — every other setting AdGuard Home
     * manages itself is left untouched.
     */
    public function reconfigureAction()
    {
        if ($this->request->isPost()) {
            (new Backend())->configdRun('adguardhome apply');
        }

        return parent::reconfigureAction();
    }
}
