select 
  weeks.`itemId`
, weeks.`pedidoId`
, weeks.`data de compra`
, weeks.`data de compensação` as `data de recebimento`
, if(weeks.`data de compensação` <= cast(now() as date), 'repassável', 'futuro') as `classificação do recebível`
, weeks.`edição`
, weeks.`evento`
, weeks.`categoria`
, case when weeks.`categoria` = 'extra'
       then 'extra'
       else weeks.`prova`
       end as `prova`
, weeks.`ticket`
, weeks.`tipo do ticket`
, weeks.`item fracionado`
, case when weeks.`forma de pgto` = 'Cortesia'
       then 0
       else weeks.`preço cadastrado`
       end as `preço cheio cadastrado`
, weeks.`status do pedido`
, weeks.`status do item`
, weeks.`discriminação`
, weeks.`ticket correlacionado`
, weeks.`forma de pgto`
, weeks.`bandeira`
, weeks.`gateway`
, weeks.`OR`
, weeks.`custo de gateway`

-- taxas
, weeks.`taxa de conveniência`
, weeks.`taxa de emissão`
, weeks.`fixo de emissão`
, weeks.`taxa de reembolso`
, weeks.`taxa de troca`

-- parcelas
, if(weeks.`forma de pgto` <> 'CreditCard', 0, weeks.`parcelas`) as `qtde de parcelas`
, if(weeks.`forma de pgto` <> 'CreditCard', 0, weeks.`parcela`) as `nº da parcela`
, if(weeks.`total do item parcelado` < 0, 0, weeks.`total do item parcelado`) as `valor da parcela` -- pago

-- tickets e extras (itens)
, case when weeks.`forma de pgto` = 'Cortesia' 
       then 0
       else weeks.`preço cadastrado parcelado`
       end as `item bruto`
, case when weeks.`forma de pgto` = 'Cortesia'
       then 0
       when weeks.`desconto parcelado` > weeks.`preço cadastrado parcelado`
       then weeks.`preço cadastrado parcelado`
       when weeks.`categoria` = 'extra' and weeks.`forma de pgto` = 'Cortesia'
       then weeks.`preço cadastrado` / case when isnull(weeks.`parcelas`) or weeks.`parcelas` = 0 then 1 else weeks.`parcelas` end
       else weeks.`desconto parcelado`
       end as `desconto`
, case when weeks.`forma de pgto` = 'Cortesia' 
       then 0
       else weeks.`preço cadastrado parcelado` - case when weeks.`forma de pgto` = 'Cortesia'
                 then 0
                 when weeks.`desconto parcelado` > weeks.`preço cadastrado parcelado`
                 then weeks.`preço cadastrado parcelado`
                 when weeks.`categoria` = 'extra' and weeks.`forma de pgto` = 'Cortesia'
                 then weeks.`preço cadastrado` / case when isnull(weeks.`parcelas`) or weeks.`parcelas` = 0 then 1 else weeks.`parcelas` end
                 else weeks.`desconto parcelado`
                 end
       end as `item líquido`
, weeks.`conveniência parcelada` as `GD - conveniência`
, weeks.`repasse de items` as `produtor - repasse de itens`     -- itens = ticket ou plugin

-- receitas de emissão ou comissão
, weeks.`emissão percentual GD` as `GD - emissão percentual`
, weeks.`emissão fixa GD` as `GD - emissão fixa`

-- reembolso/seguro
, weeks.`reembolso parcelado` as `reembolso`
, weeks.`reembolso GD parcelado` as `GD - reembolso`
, weeks.`repasse parcelado de reembolso` as `produtor - repasse de reembolso`

-- transferência de tickets
, weeks.`troca parcelada` as `transferência de ticket`
, weeks.`troca GD parcelada` as `GD - transferência`
, weeks.`repasse parcelado de troca` as `repasse - transferência`

-- que não afetam repasse (tudo da GD) -> juros e frete
, weeks.`juros parcelado` as `GD - juros`
, weeks.`frete parcelado` as `GD - frete`

, weeks.`repasse final` as `produtor - repasse total`
, weeksarrange.`semana` as `semana de recebimento`

from (
select 
  receitas_GD.*
-- para editar o repasse final, inserir ou excluir campos
, (
  receitas_GD.`repasse de items` + 
  receitas_GD.`repasse parcelado de reembolso` + 
  receitas_GD.`repasse parcelado de troca`
  ) - (
  receitas_GD.`emissão percentual GD` + 
  receitas_GD.`emissão fixa GD`
  ) as `repasse final`

, ifnull(gateCharges.`chargeType`, 'Cortesia') as `tipo de cobrança do gateway`
, ifnull(gateCharges.`chargeAmount`, 0) as `taxa do gateway`

-- custo de gateway: incide sobre o checkout inteiro
, (receitas_GD.`total do item parcelado` * ifnull(gateCharges.`chargeAmount`, 0) + receitas_GD.`custos fixos de gateway`) as `custo de gateway`

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
, 1 / cast(if(items.`parcelas` = 0, 1, items.`parcelas`) as double) as `item fracionado`
, if(items.`forma de pgto` <> 'CreditCard', 1, jt.`parcela`) as `parcela`
, date_add(items.`data de compra`, interval jt.`parcela` * if(items.`forma de pgto` <> 'CreditCard', 0, jt.`parcela`) day) as `data de compensação`
, (items.`tax` * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`) as `conveniência parcelada`
, (items.`ticketInsurance` * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`) as `reembolso parcelado`
, (items.`discount` * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`) as `desconto parcelado`
, (items.`interest` * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`) as `juros parcelado`
, (items.`freight` * items.`proporção nos extras`) / if(items.`parcelas` = 0, 1, items.`parcelas`) as `frete parcelado`
, (items.`ticketTransfer` * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`) as `troca parcelada`
-- , (items.`totalAmount` * items.`proporção no pedido`) / if(items.`parcelas` = 0, 1, items.`parcelas`) as `total do item parcelado`
, case when items.`categoria` = 'ticket'
       then ((ifnull(items.`ticketsValue`,0) + ifnull(items.`tax`,0) + ifnull(items.`ticketInsurance`,0) + ifnull(items.`interest`,0) + ifnull(items.`freight`,0) - ifnull(items.`discount`,0)) * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`)
       when items.`categoria` = 'extra'
       then (items.`productsValue` * items.`proporção nos extras`) / if(items.`parcelas` = 0, 1, items.`parcelas`)
       end as `total do item parcelado`

, case when items.`categoria` = 'ticket'
      then (items.`liquidTickets` * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`)
      else (items.`productsValue` * items.`proporção nos extras`) / if(items.`parcelas` = 0, 1, items.`parcelas`)
      end as `repasse de items`

, case when items.`categoria` = 'ticket'
      then (items.`ticketsValue` * items.`proporção nos tickets`) / if(items.`parcelas` = 0, 1, items.`parcelas`)
      else (items.`productsValue` * items.`proporção nos extras`) / if(items.`parcelas` = 0, 1, items.`parcelas`)
      end as `preço cadastrado parcelado`

from (
select 
  'tickets' as `query`
, checkoutparticipant.`id` as `itemId`
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
, ifnull(checkoutpayment.`installments`, 0) as `parcelas`
, if(isnull(installmentsrange.`installmentsArray`), '[0]', installmentsrange.`installmentsArray`) as `installmentsArray`
, ifnull(if(checkoutpayment.`paymentOption` = 'PayPal', 'PayPal', paymentprovider.`name`), 'Cortesia') as `gateway`
, case when checkoutpayment.`paymentOption` = 'PayPal' 
       then checkoutpaypaldetails.`captureId` 
       else checkoutsession.`providerOrderId` end as `OR`
, event.`taxaevent` / 100 as `taxa de conveniência`
, case when eventticketcomplement.`emissionChargePercent` = 0 or eventticketcomplement.`emissionChargePercent` is null 
       then eventcomplement.`emissionChargePercent` / 100
       else eventticketcomplement.`emissionChargePercent` / 100 end as `taxa de emissão`
, case when eventticketcomplement.`emissionChargeFixed` = 0 or eventticketcomplement.`emissionChargeFixed` is null
       then eventcomplement.`emissionChargeFixed`
       else eventticketcomplement.`emissionChargeFixed` end as `fixo de emissão`
, case when eventticketcomplement.`comissionSecurityPerc` = 0 or eventticketcomplement.`comissionSecurityPerc` is null
       then eventcomplement.`comissionSecurityPerc` / 100
       else eventticketcomplement.`comissionSecurityPerc` / 100 end as `taxa de reembolso`
, case when eventticketcomplement.`transferPercent` = 0 or eventticketcomplement.`transferPercent` is null
       then eventcomplement.`transferPercent` / 100
       else eventticketcomplement.`transferPercent` / 100 end as `taxa de troca`
, eventcomplement.`rebateTax` / 100 as `taxa de rebate`
, eventcomplement.`taxRate` / 100 as `taxa de impostos`
, ifnull(ifnull(pagarme_fixed_charges.`chargeAmountFixed`, 0) / ifnull(checkoutpayment.`installments`, 1), 0) as `custos fixos de gateway`
-- SUMMARY TICKETS
, case when isnull(checkoutsummary.`totalAmount`)
       then 0
       when checkoutsummary.`totalAmount` <= 0 or checkoutpayment.`paymentoption` is null
       then 0
       else checkoutsummary.`totalAmount`
       end as `totalAmount`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       else ifnull(checkoutsummary.`ticketsValue`,0) 
       end as `ticketsValue`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       when checkoutpayment.`paymentoption` is null
       then 0
       else if(
           ifnull(checkoutsummary.`ticketsValue`,0) + ifnull(checkoutsummary.`tax`,0) <= ifnull(checkoutsummary.`discount`,0),
           0,
           ifnull(checkoutsummary.`ticketsValue`,0) - ifnull(checkoutsummary.`discount`,0)
           )
       end as `liquidTickets`
, 0 as `productsValue`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       when ifnull(checkoutsummary.`totalAmount`,0) >= 0
       then ifnull(checkoutsummary.`discount`,0)
       else checkoutsummary.`ticketsValue` + checkoutsummary.`interest` + checkoutsummary.`freight` + checkoutsummary.`tax` + checkoutsummary.`ticketInsurance`
       end as `discount`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       when ifnull(checkoutsummary.`totalAmount`,0) <= 0
       then 0
       else ifnull(checkoutsummary.`interest`,0) 
       end as `interest`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0 
       when ifnull(checkoutsummary.`totalAmount`,0) <= 0
       then 0
       else ifnull(checkoutsummary.`freight`,0) 
       end as `freight`
, case when checkoutsummary.`ticketTransfer` > 0 
       then 0 
       when ifnull(checkoutsummary.`totalAmount`,0) <= 0
       then 0
       else ifnull(checkoutsummary.`tax`,0) 
       end as `tax`
, case when checkoutsummary.`ticketTransfer` > 0
       then 0
       when ifnull(checkoutsummary.`totalAmount`,0) <= 0
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
, case when ifnull(eventticketbatchprice.`price` / ifnull(checkoutsummary.`totalAmount`,0),0) < 0
       then 0
       else ifnull(eventticketbatchprice.`price` / ifnull(checkoutsummary.`totalAmount`,0),0)
       end as `proporção no pedido`
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
    checkoutorderticketpartialcancel.`reason` in ('Troca de Titularidade', 'Cancelamento Reembolsável')    -- opt para 'another option' -> 'Cancelamento Reembolsável', 'Cancelamento (7 dias)', 'Desistência'
    )
  and {{edicao}}
  and {{pedidoId}}
  and {{eventId}}
  and {{participanteId}}
[[and case when 1 in (select {{extraId}} from checkoutproductcomplement) then checkoutparticipant.`id` < 0 else false end]]


union all


select 
  'extras' as `query`
, checkoutproductcomplement.`id` as `itemId`
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
, ifnull(checkoutpayment.`installments`, 0) as `parcelas`
, if(isnull(installmentsrange.`installmentsArray`), '[0]', installmentsrange.`installmentsArray`) as `installmentsArray`
, ifnull(if(checkoutpayment.`paymentOption` = 'PayPal', 'PayPal', paymentprovider.`name`), 'Cortesia') as `gateway`
, case when checkoutpayment.`paymentOption` = 'PayPal' 
       then checkoutpaypaldetails.`captureId` 
       else checkoutsession.`providerOrderId` end as `OR`
, event.`taxaevent` / 100 as `taxa de conveniência`
, case when productcomplementmanual.`productChargePercent` is null or productcomplementmanual.`productChargePercent` = 0
       then eventcomplement.`productChargePercent` / 100
       else productcomplementmanual.`productChargePercent` / 100 end as `taxa de emissão`
, case when productcomplementmanual.`productChargeFixed` is null or productcomplementmanual.`productChargeFixed` = 0
       then eventcomplement.`productChargeFixed`
       else productcomplementmanual.`productChargeFixed` end as `fixo de emissão`
, 0 as `taxa de reembolso`
, 0 as `taxa de troca`
, 0 as `taxa de rebate`
, eventcomplement.`taxRate` / 100 as `taxa de impostos`
, ifnull(ifnull(pagarme_fixed_charges.`chargeAmountFixed`, 0) / ifnull(checkoutpayment.`installments`, 1), 0) as `custos fixos de gateway`
-- SUMMARY EXTRAS
, case when isnull(checkoutpayment.`paymentoption`) or isnull(checkoutsummary.`totalAmount`) or checkoutsummary.`totalAmount` <= 0
       then 0
       else checkoutsummary.`totalAmount`
       end as `totalAmount`
, 0 as `ticketsValue`
, 0 as `liquidTickets`
, case when isnull(checkoutpayment.`paymentoption`)
       then 0 
       else ifnull(checkoutsummary.`productsValue`,0) 
       end as `productsValue`
, 0 as `discount`
, case when isnull(checkoutpayment.`paymentoption`) 
       then 0 
       else ifnull(checkoutsummary.`interest`,0)
       end as `interest`
, case when isnull(checkoutpayment.`paymentoption`)
       then 0 
       else ifnull(checkoutsummary.`freight`,0) 
       end as `freight`
, 0 as `tax`
, 0 as `ticketInsurance`
, 0 as `ticketTransfer`
, productsize.`price` as `preço cadastrado`
, 0 as `proporção nos tickets`
, ifnull(productsize.`price` / checkoutsummary.`productsValue`,0) as `proporção nos extras`
, case when ifnull(productsize.`price` / ifnull(checkoutsummary.`totalAmount`,0),0) < 0
       then 0 
       else ifnull(productsize.`price` / ifnull(checkoutsummary.`totalAmount`,0),0) 
       end as `proporção no pedido`
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
    checkoutorderproductpartialcancel.`reason` in ('another option')    -- opt para 'another option' -> 'Cancelamento Reembolsável', 'Cancelamento (7 dias)', 'Desistência'
      )
  and {{edicao}}
  and {{pedidoId}}
  and {{eventId}}
  and {{extraId}}
[[and case when 1 in (select {{participanteId}} from checkoutparticipant) then checkoutproductcomplement.`id` < 0 else false end]]

) as items

join json_table( items.`installmentsArray`, '$[*]' columns (`parcela` int path '$') ) as jt

order by items.`pedidoID` desc

) as parcelas
) as receitas_GD

left join gateCharges on 
    concat(gateCharges.`gateway`, '_', gateCharges.`negotiationNumber`, '_', gateCharges.`chargeOn`, '_', gateCharges.`cardBrand`, '_', gateCharges.`installments`) = 
    concat(receitas_GD.`gateway`, '_1_', receitas_GD.`forma de pgto`, '_', if(receitas_GD.`bandeira` = 'sem bandeira', 'Master', receitas_GD.`bandeira`), '_', ifnull(receitas_GD.`parcelas`, 1))

) as weeks

left join weeksarrange on weeksarrange.`data` = weeks.`data de compensação`

where 1=1
[[and weeks.`data de compensação` between {{data_compensacao_ini}} and {{data_compensacao_fini}}]]
[[and weeks.`data de compra` between {{data_compra_ini}} and {{data_compra_fini}}]]
[[and if(weeks.`data de compensação` <= cast(now() as date), 'repassável', 'futuro') = {{classificacao}}]]
