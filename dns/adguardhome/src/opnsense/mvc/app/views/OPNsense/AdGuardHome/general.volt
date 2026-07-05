<script>
    $(document).ready(function() {
        var data_get_map = {'frm_general_settings':"/api/adguardhome/general/get"};
        mapDataToFormUI(data_get_map).done(function(data) {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        ajaxCall(url="/api/adguardhome/service/status", sendData={}, callback=function(data,status) {
            updateServiceStatusUI(data['status']);
        });

        // Open the AdGuard Home web interface. The host is the current
        // firewall; the port comes from the (link-only) Web Interface Port
        // field, defaulting to the setup-wizard port 3000.
        $("#openUiAct").click(function() {
            var port = $("#general\\.webport").val() || "3000";
            var url = window.location.protocol + "//" + window.location.hostname + ":" + port + "/";
            window.open(url, "_blank");
        });

        $("#saveAct").click(function() {
            saveFormToEndpoint(url="/api/adguardhome/general/set", formid='frm_general_settings', callback_ok=function() {
                $("#saveAct_progress").addClass("fa fa-spinner fa-pulse");
                ajaxCall(url="/api/adguardhome/service/reconfigure", sendData={}, callback=function(data,status) {
                    ajaxCall(url="/api/adguardhome/service/status", sendData={}, callback=function(data,status) {
                        updateServiceStatusUI(data['status']);
                    });
                    $("#saveAct_progress").removeClass("fa fa-spinner fa-pulse");
                });
            });
        });
    });
</script>

<div class="content-box" style="padding-bottom: 1.5em;">
    {{ partial("layout_partials/base_form", ['fields':generalForm,'id':'frm_general_settings']) }}
    <div class="col-md-12">
        <hr />
        <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i></button>
        <button class="btn btn-default" id="openUiAct" type="button"><b>{{ lang._('Open AdGuard Home') }}</b> <i class="fa fa-external-link"></i></button>
    </div>
</div>
