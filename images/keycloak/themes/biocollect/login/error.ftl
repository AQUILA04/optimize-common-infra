<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        ${kcSanitize(msg("errorTitleHtml"))?no_esc}
    <#elseif section = "form">
        <div class="biocollect-error-panel">
            <p>${kcSanitize(message.summary)?no_esc}</p>
            <div class="biocollect-error-actions">
                <#if skipLink??>
                <#elseif client?? && client.baseUrl?has_content>
                    <a class="pf-v5-c-button pf-m-primary" href="${client.baseUrl}">${kcSanitize(msg("backToApplication"))?no_esc}</a>
                <#else>
                    <a class="pf-v5-c-button pf-m-primary" href="https://biocollect.optimizesolux.com/">${kcSanitize(msg("backToBioCollect"))?no_esc}</a>
                </#if>
            </div>
        </div>
    </#if>
</@layout.registrationLayout>
