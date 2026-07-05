<?php

/*
 * Copyright (C) 2026
 * All rights reserved.
 */

namespace OPNsense\AdGuardHome;

class GeneralController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/AdGuardHome/general');
        $this->view->generalForm = $this->getForm("general");
    }
}
