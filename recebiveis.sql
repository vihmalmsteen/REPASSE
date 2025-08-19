select 
  weeks.`itemId`
, weeks.`pedidoId`
, weeks.`data de compra`
, weeks.`data de compensação`
, if(weeks.`data de compensação` <= cast(now() as date), 'repassável', 'futuro') as `classificação do recebível`
, weeksarrange.`semana` as `semana de compensação`
, weeks.`edição`
, weeks.`evento`
, weeks.`categoria`
, weeks.`prova`
, weeks.`ticket`
, weeks.`tipo do ticket`
, weeks.`item fracionado`
, weeks.`preço cadastrado`
, weeks.`status do pedido`
, weeks.`status do item`
, weeks.`discriminação`
, weeks.`ticket correlacionado`
, weeks.`forma de pgto`
, weeks.`gateway`
, weeks.`OR`
-- , weeks.`tipo de cobrança do gateway`
, weeks.`taxa do gateway`
, weeks.`taxa de conveniência`
, weeks.`taxa de extras`
, weeks.`taxa de emissão`
, weeks.`fixo de emissão`
, weeks.`taxa de reembolso`
, weeks.`taxa de troca`
, weeks.`taxa de rebate`
, weeks.`taxa de impostos`
-- , weeks.`custo adicional`
-- , weeks.`aplicação do custo adicional`
-- , weeks.`tipo do custo adicional`
, weeks.`parcelas`
, weeks.`parcela`
, weeks.`emissão percentual GD`
, weeks.`emissão fixa GD`
, weeks.`total do item parcelado`
, weeks.`preço cadastrado parcelado`
, weeks.`desconto parcelado`
, weeks.`repasse de items`
, weeks.`conveniência parcelada`
, weeks.`troca parcelada`
, weeks.`repasse parcelado de troca`
, weeks.`troca GD parcelada`
, weeks.`reembolso parcelado`
, weeks.`repasse parcelado de reembolso`
, weeks.`reembolso GD parcelado`
, weeks.`juros parcelado`
, weeks.`frete parcelado`
, weeks.`repasse final`
, weeks.`conveniência líquida parcelada`
, weeks.`custos fixos de gateway`
, weeks.`custo de gateway`
, weeks.`rebate`

from (
select 
  receitas_GD.*
, (receitas_GD.`repasse de items` + receitas_GD.`repasse parcelado de reembolso` + receitas_GD.`repasse parcelado de troca`) - (receitas_GD.`emissão percentual GD` + receitas_GD.`emissão fixa GD`) as `repasse final`
, ifnull(gateCharges.`chargeType`, 'Cortesia') as `tipo de cobrança do gateway`
, ifnull(gateCharges.`chargeAmount`, 0) as `taxa do gateway`

-- custo de gateway: incide sobre o checkout inteiro
, (receitas_GD.`total do item parcelado` * ifnull(gateCharges.`chargeAmount`, 0) + receitas_GD.`custos fixos de gateway`) as `custo de gateway`

-- conv liquida: (conveniência - custo de gateway - demais custos) x (1 - taxa de impostos) -> (se menor que zero, zero | 'demais custos' como custo de infra por item vendido)
, case when (receitas_GD.`conveniência parcelada` - ((receitas_GD.`total do item parcelado` * ifnull(gateCharges.`chargeAmount`, 0) + receitas_GD.`custos fixos de gateway`)) - receitas_GD.`valor do custo adicional`) * (1 - receitas_GD.`custo adicional`) < 0
       then 0
       else (receitas_GD.`conveniência parcelada` - (receitas_GD.`total do item parcelado` * ifnull(gateCharges.`chargeAmount`, 0) + receitas_GD.`custos fixos de gateway`) - receitas_GD.`valor do custo adicional`) * (1 - receitas_GD.`custo adicional`) 
       end as `conveniência líquida parcelada`

-- rebate: conveniência líquida parcelada x taxa de rebate -> (se menor que zero, zero)
, case when ((receitas_GD.`conveniência parcelada` - (receitas_GD.`total do item parcelado` * ifnull(gateCharges.`chargeAmount`, 0) + receitas_GD.`custos fixos de gateway`) - receitas_GD.`valor do custo adicional`) * (1 - receitas_GD.`custo adicional`)) * receitas_GD.`taxa de rebate` < 0
       then 0
       else ((receitas_GD.`conveniência parcelada` - (receitas_GD.`total do item parcelado` * ifnull(gateCharges.`chargeAmount`, 0) + receitas_GD.`custos fixos de gateway`) - receitas_GD.`valor do custo adicional`) * (1 - receitas_GD.`custo adicional`)) * receitas_GD.`taxa de rebate` 
       end as `rebate`

from (
select 
  parcelas.*
, parcelas.`reembolso parcelado` * parcelas.`taxa de reembolso` as `reembolso GD parcelado`
, parcelas.`reembolso parcelado` * (1 - parcelas.`taxa de reembolso`) as `repasse parcelado de reembolso`
, parcelas.`troca parcelada` * parcelas.`taxa de troca` as `troca GD parcelada`
, parcelas.`troca parcelada` * (1 - parcelas.`taxa de troca`) as `repasse parcelado de troca`

-- Sobre cobranças de emissão, depende bastante do que deve ser considerado. Somente emissão de tickets de cortesias? Somente assessorias? Ambos? Outra coisa? Etc.
, if(parcelas.`parcela` <= 1, parcelas.`repasse de items` * parcelas.`taxa de emissão` * parcelas.`parcelas`, 0) as `emissão percentual GD`
, if(parcelas.`parcela` > 1 or parcelas.`discriminação` = 'Troca de Titularidade (para)' or parcelas.`forma de pgto` <> 'Cortesia', 0, parcelas.`fixo de emissão`) as `emissão fixa GD`

from (
select
  items.* 
, 1 / cast(items.`parcelas` as double) as `item fracionado`
, if(items.`forma de pgto` <> 'CreditCard', 1, jt.`parcela`) as `parcela`
, date_add(items.`data de compra`, interval jt.`parcela` * if(items.`forma de pgto` <> 'CreditCard', 0, jt.`parcela`) day) as `data de compensação`
, (items.`tax` * items.`proporção nos tickets`) / items.`parcelas` as `conveniência parcelada`
, (items.`ticketInsurance` * items.`proporção nos tickets`) / items.`parcelas` as `reembolso parcelado`
, (items.`discount` * items.`proporção nos tickets`) / items.`parcelas` as `desconto parcelado`
, (items.`interest` * items.`proporção no pedido`) / items.`parcelas` as `juros parcelado`
, (items.`freight` * items.`proporção no pedido`) / items.`parcelas` as `frete parcelado`
, (items.`ticketTransfer` * items.`proporção nos tickets`) / items.`parcelas` as `troca parcelada`
, (items.`totalAmount` * items.`proporção no pedido`) / items.`parcelas` as `total do item parcelado`

, case when items.`categoria` = 'ticket'
      then (items.`liquidTickets` * items.`proporção nos tickets`) / items.`parcelas`
      else (items.`productsValue` * items.`proporção nos extras`) / items.`parcelas`
      end as `repasse de items`

, case when items.`categoria` = 'ticket'
      then (items.`ticketsValue` * items.`proporção nos tickets`) / items.`parcelas`
      else (items.`productsValue` * items.`proporção nos extras`) / items.`parcelas`
      end as `preço cadastrado parcelado`

from (
select 
  checkoutparticipant.`id` as `itemId`
, checkoutsession.`id` as `pedidoId`
, cast(date_add(checkoutsession.`createdat`, interval -3 hour) as date) as `data de compra`
, eventcomplement.`globalevent` as `edição`
, event.`title` as `evento`
, eventticketcomplement.`category` as `categoria`
, eventticketcomplement.`nameparsed` as `prova`
, eventticket.`name` as `ticket`
, eventticketbatchpricetype.`name` as `tipo do ticket`
, checkoutsession.`status` as `status do pedido`
, ifnull(checkoutpayment.`paymentoption`, 'Cortesia') as `forma de pgto`
, ifnull(checkoutpayment.`installments`, 1) as `parcelas`
, if(isnull(installmentsrange.`installmentsArray`), '[0]', installmentsrange.`installmentsArray`) as `installmentsArray`
, ifnull(if(checkoutpayment.`paymentOption` = 'PayPal', 'PayPal', paymentprovider.`name`), 'Cortesia') as `gateway`
, case when checkoutpayment.`paymentOption` = 'PayPal' 
       then checkoutpaypaldetails.`captureId` 
       else checkoutsession.`providerOrderId` end as `OR`
, event.`taxaevent` / 100 as `taxa de conveniência`
, 0 as `taxa de extras`
, eventcomplement.`emissionChargePercent` / 100 as `taxa de emissão`
, eventcomplement.`emissionChargeFixed` as `fixo de emissão`
, eventcomplement.`comissionSecurityPerc` / 100 as `taxa de reembolso`
, eventcomplement.`transferPercent` / 100 as `taxa de troca`
, eventcomplement.`rebateTax` / 100 as `taxa de rebate`
, eventcomplement.`taxRate` / 100 as `taxa de impostos`

, ifnull(eventAdditionalCosts.`label`, 'não aplicável') as `custo adicional`
, ifnull(eventAdditionalCosts.`applyOn`, 'não aplicável') as `aplicação do custo adicional`
, ifnull(eventAdditionalCosts.`type`, 'não aplicável') as `tipo do custo adicional`
, case when eventAdditionalCosts.`type` is null
       then 0
       when eventAdditionalCosts.`type` = 'fixed'
       then ifnull(eventAdditionalCosts.`value`, 0) / ifnull(checkoutpayment.`installments`, 1)
       when eventAdditionalCosts.`type` = 'percent'
       then ifnull(eventAdditionalCosts.`value`, 0) / 100
       else ifnull(eventAdditionalCosts.`value`, 0)
       end as `valor do custo adicional`
, ifnull(ifnull(pagarme_fixed_charges.`chargeAmountFixed`, 0) / ifnull(checkoutpayment.`installments`, 1), 0) as `custos fixos de gateway`
, if(isnull(checkoutsummary.`totalAmount`) or checkoutsummary.`totalAmount` < 0, 0, checkoutsummary.`totalAmount`) as `totalAmount`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       else ifnull(checkoutsummary.`ticketsValue`,0) 
       end as `ticketsValue`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       else if(ifnull(checkoutsummary.`ticketsValue`,0) + ifnull(checkoutsummary.`tax`,0) <= ifnull(checkoutsummary.`discount`,0), 0, ifnull(checkoutsummary.`ticketsValue`,0) - ifnull(checkoutsummary.`discount`,0)) 
       end as `liquidTickets`
, 0 as `productsValue`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       else if(ifnull(checkoutsummary.`ticketsValue`,0) + ifnull(checkoutsummary.`tax`,0) <= ifnull(checkoutsummary.`discount`,0), ifnull(checkoutsummary.`discount`,0), ifnull(checkoutsummary.`discount`,0)) 
       end as `discount`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       else ifnull(checkoutsummary.`interest`,0) 
       end as `interest`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0 
       else ifnull(checkoutsummary.`freight`,0) 
       end as `freight`
, case when checkoutsummary.`ticketTransfer` > 0 
       then 0 
       else ifnull(checkoutsummary.`tax`,0) 
       end as `tax`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       else ifnull(checkoutsummary.`ticketInsurance`,0) 
       end as `ticketInsurance`
, ifnull(checkoutsummary.`ticketTransfer`,0) as `ticketTransfer`
, case when checkoutsummary.`ticketTransfer` > 0
       then event.`ticketTransferValue`
       else eventticketbatchprice.`price` 
       end as `preço cadastrado`
, ifnull(eventticketbatchprice.`price` / checkoutsummary.`ticketsValue`,0) as `proporção nos tickets`
, 0 as `proporção nos extras`
, ifnull(eventticketbatchprice.`price` / (ifnull(checkoutsummary.`ticketsValue`,0) + ifnull(checkoutsummary.`productsValue`,0)),0) `proporção no pedido`
, case when checkoutorderticketpartialcancel.`reason` = 'Troca de Titularidade'
       then 'transferido'
       when checkoutsummary.`ticketTransfer` > 0
       then 'recebido'
       when checkoutorderticketpartialcancel.`reason` is null
       then 'aprovado'
       else 'cancelado' end as `status do item`
, case when checkoutorderticketpartialcancel.`reason` = 'Troca de Titularidade'
       then 'Troca de Titularidade (de)'
       when checkoutsummary.`ticketTransfer` > 0
       then 'Troca de Titularidade (para)'
       when checkoutorderticketpartialcancel.`reason` is null
       then 'aprovado'
       else checkoutorderticketpartialcancel.`reason`
       end as `discriminação`
, ifnull(tradeNewItem.`oldItemId`, tradeOldItem.`newItemId`) as `ticket correlacionado`
, case when checkoutpayment.`paymentOption` is null
       then 'Cortesia'
       when checkoutpayment.`paymentOption` <> 'CreditCard' 
       then checkoutpayment.`paymentOption`
       when customerpaymentprovidercard.`brand` = 'mastercard'
       then 'Master'
       when customerpaymentprovidercard.`brand` is null and checkoutpayment.`cardBrand` is not null 
       then checkoutpayment.`cardBrand`
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('40', '41', '42', '43', '44', '45', '46', '47', '48', '49') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('40', '41', '42', '43', '44', '45', '46', '47', '48', '49')
       then 'visa'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('22', '23', '24', '25', '26', '27', '51', '52', '53', '54', '55') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('22', '23', '24', '25', '26', '27', '51', '52', '53', '54', '55')
       then 'Master'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('50', '63', '65') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('50', '63', '65')
       then 'elo'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('38', '60') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('38', '60')
       then 'hipercard'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('34', '35', '36', '37') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('34', '35', '36', '37')
       then 'Amex'
       when customerpaymentprovidercard.`brand` is null and checkoutpayment.`cardBrand` is null 
       then 'sem bandeira'
       else customerpaymentprovidercard.`brand` end as `bandeira`
, case when checkoutpayment.`paymentOption` is null
       then 'Cortesia'
       when customerpaymentprovidercard.`first_six_digits` = '******' and checkoutpayment.`cardFirstSixDigits` = '******'
       then 'masked'
       when (customerpaymentprovidercard.`first_six_digits` is null or customerpaymentprovidercard.`first_six_digits` = '******') and (checkoutpayment.`cardFirstSixDigits` is not null and checkoutpayment.`cardFirstSixDigits` <> '******')
       then left(checkoutpayment.`cardFirstSixDigits`, 4)
       else left(customerpaymentprovidercard.`first_six_digits`, 4) end as `primeiros dígitos do cartão`

from checkoutparticipant
    left join checkoutsession                       on checkoutsession.`id` = checkoutparticipant.`sessionid`
    left join checkoutsummary                       on checkoutsummary.`sessionid` = checkoutsession.`id`
    left join checkoutorderticketpartialcancel      on checkoutorderticketpartialcancel.`participantId` = checkoutparticipant.`id`
    left join checkouteventticketbatchprice         on checkouteventticketbatchprice.`id` = checkoutparticipant.`checkoutEventTicketBatchPriceId`
    left join eventticketbatchprice                 on eventticketbatchprice.`id` = checkouteventticketbatchprice.`eventTicketBatchPriceId`
    left join eventticketbatchpricetype             on eventticketbatchpricetype.`id` = eventticketbatchprice.`typeid`
    left join eventticketbatch                      on eventticketbatch.`id` = eventticketbatchprice.`ticketBatchId`
    left join eventticket                           on eventticket.`id` = eventticketbatch.`ticketId`
    left join event                                 on event.`id` = eventticket.`eventid`
    left join eventticketcomplement                 on eventticketcomplement.`ticketid` = eventticket.`id`
    left join eventcomplement                       on eventcomplement.`eventid` = event.`id`
    left join checkoutpayment                       on checkoutpayment.`sessionid` = checkoutsession.`id`
    left join installmentsrange                     on installmentsrange.`installments` = checkoutpayment.`installments`
    left join paymentprovider                       on paymentprovider.`id` = checkoutpayment.`paymentProviderId`
    left join checkoutpaypaldetails                 on checkoutpaypaldetails.`sessionId` = checkoutsession.`id`
    
    left join (
        select * 
            from eventAdditionalCosts 
        where label = 'custo de infra'
    ) as eventAdditionalCosts on eventAdditionalCosts.`eventid` = event.`id`
    
    left join (
        select 
          checkoutsession.`id` as `sessionId`
        , customerpaymentprovidercard.`cardId`
        , customerpaymentprovidercard.`first_six_digits`
        , customerpaymentprovidercard.`brand`
        from customerpaymentprovidercard
	        join checkoutsession on checkoutsession.`providerCardId` = customerpaymentprovidercard.`cardId`
        group by checkoutsession.`id`
    ) as customerpaymentprovidercard on customerpaymentprovidercard.`sessionId` = checkoutsession.`id`
    
    left join (
        select 
          tradecheckoutsession.`originalParticipantId` as `newItemId`
        , tradecheckoutsession.`participantId` as `oldItemId`
        , tradecheckoutsession.`transferValue` as `trocaValor`
        from tradecheckoutsession
        where tradecheckoutsession.`status` = 'Paid'
    ) as tradeNewItem on tradeNewItem.`newItemId` = checkoutparticipant.`id`
    
    left join (
        select 
          tradecheckoutsession.`originalParticipantId` as `newItemId`
        , tradecheckoutsession.`participantId` as `oldItemId`
        , tradecheckoutsession.`transferValue` as `trocaValor`
        from tradecheckoutsession
        where tradecheckoutsession.`status` = 'Paid'
    ) as tradeOldItem on tradeOldItem.`oldItemId` = checkoutparticipant.`id`
    
    left join (
        select `gateway`, sum(`chargeAmount`) as `chargeAmountFixed`
        from gatecharges 
        where `chargetype` = 'fixed'
          and `chargeon` <> 'boleto'
        group by `gateway`
    ) as pagarme_fixed_charges on pagarme_fixed_charges.`gateway` = if(checkoutpayment.`paymentOption` = 'PayPal', 'PayPal', paymentprovider.`name`)
    
where 1 = 1
  and checkoutsession.`status` = 'Paid'
  and ( 
    checkoutorderticketpartialcancel.`reason` is null or
    checkoutorderticketpartialcancel.`reason` in ('Troca de Titularidade', 'Cancelamento Reembolsável')                   -- 'Cancelamento Reembolsável', 'Cancelamento (7 dias)', 'Arrependimento', 'Troca de Titularidade', 'Desistência'
    )
  and eventcomplement.`globalevent` = 'edição XPTO'
  and {{pedidoId}}
  and {{eventId}}
  and {{participanteId}}
[[and case when 1 in (select {{extraId}} from checkoutproductcomplement) then checkoutparticipant.`id` < 0 else false end]]


union all


select 
  checkoutproductcomplement.`id` as `itemId`
, checkoutsession.`id` as `pedidoId`
, cast(date_add(checkoutsession.`createdat`, interval -3 hour) as date) as `data de compra`
, eventcomplement.`globalevent` as `edição`
, event.`title` as `evento`
, productcomplementmanual.`category` as `categoria`
, '-' as `prova`
, product.`title` as `item`
, productmodel.`name` as `tipo do ticket`
, checkoutsession.`status` as `status do pedido`
, ifnull(checkoutpayment.`paymentoption`, 'Cortesia') as `forma de pgto`
, checkoutpayment.`installments` as `parcelas`
, installmentsrange.`installmentsArray`
, if(checkoutpayment.`paymentOption` = 'PayPal', 'PayPal', paymentprovider.`name`) as `gateway`
, case when checkoutpayment.`paymentOption` = 'PayPal' 
       then checkoutpaypaldetails.`captureId` 
       else checkoutsession.`providerOrderId` end as `OR`
, event.`taxaevent` / 100 as `taxa de conveniência`
, eventcomplement.`productChargePercent` / 100 as `taxa de extras`
, eventcomplement.`emissionChargePercent` / 100 as `taxa de emissão`
, 0 as `fixo de emissão`
, 0 as `taxa de reembolso`
, 0 as `taxa de troca`
, 0 as `taxa de rebate`
, eventcomplement.`taxRate` / 100 as `taxa de impostos`
, 'não aplicável' as `custo adicional`              -- extra não tem conv
, 'não aplicável' as `aplicação do custo adicional` -- extra não tem conv
, 'não aplicável' as `tipo do custo adicional`      -- extra não tem conv
, 0 as `valor do custo adicional`                   -- extra não tem conv
, ifnull(ifnull(pagarme_fixed_charges.`chargeAmountFixed`, 0) / ifnull(checkoutpayment.`installments`, 1), 0) as `custos fixos de gateway`
, ifnull(checkoutsummary.`totalAmount`,0) as `totalAmount`
, 0 as `ticketsValue`
, 0 as `liquidTickets`
, ifnull(checkoutsummary.`productsValue`,0) as `productsValue`
, 0 as `discount`
, ifnull(checkoutsummary.`interest`,0) as `interest`
, ifnull(checkoutsummary.`freight`,0) as `freight`
, 0 as `tax`
, 0 as `ticketInsurance`
, 0 as `ticketTransfer`
, productsize.`price` as `preço cadastrado`
, 0 as `proporção nos tickets`
, ifnull(productsize.`price` / checkoutsummary.`productsValue`,0) as `proporção nos extras`
, ifnull(productsize.`price` / (ifnull(checkoutsummary.`ticketsValue`,0) + ifnull(checkoutsummary.`productsValue`,0)),0) `proporção no pedido`

, case when checkoutorderproductpartialcancel.`reason` = 'Troca de Titularidade'
       then 'aprovado'
       when checkoutorderproductpartialcancel.`reason` is null
       then 'aprovado'
       else 'cancelado' end as `status do item`

, case when checkoutorderproductpartialcancel.`reason` = 'Troca de Titularidade'
       then 'aprovado'
       when checkoutorderproductpartialcancel.`reason` is null
       then 'aprovado'
       else checkoutorderproductpartialcancel.`reason`
       end as `discriminação`

, null as `ticket correlacionado`

, case when checkoutpayment.`paymentOption` is null
       then 'Cortesia'
       when checkoutpayment.`paymentOption` <> 'CreditCard' 
       then checkoutpayment.`paymentOption`
       when customerpaymentprovidercard.`brand` = 'mastercard'
       then 'Master'
       when customerpaymentprovidercard.`brand` is null and checkoutpayment.`cardBrand` is not null 
       then checkoutpayment.`cardBrand`
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('40', '41', '42', '43', '44', '45', '46', '47', '48', '49') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('40', '41', '42', '43', '44', '45', '46', '47', '48', '49')
       then 'visa'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('22', '23', '24', '25', '26', '27', '51', '52', '53', '54', '55') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('22', '23', '24', '25', '26', '27', '51', '52', '53', '54', '55')
       then 'Master'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('50', '63', '65') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('50', '63', '65')
       then 'elo'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('38', '60') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('38', '60')
       then 'hipercard'
       when left(checkoutpayment.`cardFirstSixDigits`, 2) in ('34', '35', '36', '37') or left(customerpaymentprovidercard.`first_six_digits`, 2) in ('34', '35', '36', '37')
       then 'Amex'
       when customerpaymentprovidercard.`brand` is null and checkoutpayment.`cardBrand` is null 
       then 'Master'
       else customerpaymentprovidercard.`brand` end as `bandeira`
, case when checkoutpayment.`paymentOption` is null
       then 'Cortesia'
       when customerpaymentprovidercard.`first_six_digits` = '******' and checkoutpayment.`cardFirstSixDigits` = '******'
       then 'masked'
       when (customerpaymentprovidercard.`first_six_digits` is null or customerpaymentprovidercard.`first_six_digits` = '******') and (checkoutpayment.`cardFirstSixDigits` is not null and checkoutpayment.`cardFirstSixDigits` <> '******')
       then left(checkoutpayment.`cardFirstSixDigits`, 4)
       else left(customerpaymentprovidercard.`first_six_digits`, 4) end as `primeiros dígitos do cartão`

from checkoutproductcomplement
    left join checkoutsession                       on checkoutsession.`id` = checkoutproductcomplement.`sessionId`
    left join checkoutbuyer                         on checkoutbuyer.`sessionId` = checkoutproductcomplement.`sessionId`
    left join product                               on product.`id` = checkoutproductcomplement.`productId`
    left join productmodel                          on productmodel.`id` = checkoutproductcomplement.`modelId`
    left join productsize                           on productsize.`id` = checkoutproductcomplement.`sizeId`
    left join productcomplementmanual               on productcomplementmanual.`productId` = checkoutproductcomplement.`productId`
    left join checkoutpayment                       on checkoutpayment.`sessionId` = checkoutsession.`id`
    left join installmentsrange                     on installmentsrange.`installments` = checkoutpayment.`installments`
    left join event                                 on event.`id` = product.`eventId`
    left join eventcomplement                       on eventcomplement.`eventId` = event.`id`
    left join paymentprovider                       on paymentprovider.`id` = checkoutpayment.`paymentProviderId`
    left join checkoutsummary                       on checkoutsummary.`sessionid` = checkoutsession.`id`
    left join checkoutpaypaldetails                 on checkoutpaypaldetails.`sessionId` = checkoutsession.`id`
    left join checkoutorderproductpartialcancel     on checkoutorderproductpartialcancel.`checkoutProductComplementId` = checkoutproductcomplement.`id`
    left join checkoutproductcomplementanswer       on checkoutproductcomplementanswer.`checkoutProductComplementId` = checkoutproductcomplement.`id`
    
    left join (
        select 
          checkoutsession.`id` as `sessionId`
        , customerpaymentprovidercard.`cardId`
        , customerpaymentprovidercard.`first_six_digits`
        , customerpaymentprovidercard.`brand`
        from customerpaymentprovidercard
	        join checkoutsession on checkoutsession.`providerCardId` = customerpaymentprovidercard.`cardId`
        group by checkoutsession.`id`
    ) as customerpaymentprovidercard on customerpaymentprovidercard.`sessionId` = checkoutsession.`id`
    
    left join (
        select `gateway`, sum(`chargeAmount`) as `chargeAmountFixed`
        from gatecharges 
        where `chargetype` = 'fixed'
          and `chargeon` <> 'boleto'
        group by `gateway`
    ) as pagarme_fixed_charges on pagarme_fixed_charges.`gateway` = if(checkoutpayment.`paymentOption` = 'PayPal', 'PayPal', paymentprovider.`name`)

where 1 = 1
  and checkoutsession.`status` = 'Paid'
  and ( 
    checkoutorderproductpartialcancel.`reason` is null or 
    checkoutorderproductpartialcancel.`reason` in ('another option')                                                       -- 'Cancelamento Reembolsável', 'Cancelamento (7 dias)', 'Desistência'
      )
  and eventcomplement.`globalevent` = 'edição XPTO'
  and {{pedidoId}}
  and {{eventId}}
  and {{extraId}}
[[and case when 1 in (select {{participanteId}} from checkoutparticipant) then checkoutproductcomplement.`id` < 0 else false end]]

) as items

join json_table( items.`installmentsArray`, '$[*]' columns (`parcela` int path '$') ) as jt

) as parcelas
) as receitas_GD


left join gateCharges on 
    concat(gateCharges.`gateway`, '_', gateCharges.`negotiationNumber`, '_', gateCharges.`chargeOn`, '_', gateCharges.`cardBrand`, '_', gateCharges.`installments`) = 
    concat(receitas_GD.`gateway`, '_1_', receitas_GD.`forma de pgto`, '_', if(receitas_GD.`bandeira` = 'sem bandeira', 'Master', receitas_GD.`bandeira`), '_', ifnull(receitas_GD.`parcelas`, 1))

) as weeks

left join weeksarrange on weeksarrange.`data` = weeks.`data de compensação`
