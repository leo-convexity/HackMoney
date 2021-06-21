import { MouseoverTooltip, MouseoverTooltipContent } from 'components/Tooltip'
import JSBI from 'jsbi'
import React, { useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { ArrowDown, CheckCircle, HelpCircle, Info, ArrowLeft } from 'react-feather'
import ReactGA from 'react-ga'
import { Link, RouteComponentProps } from 'react-router-dom'
import { Text } from 'rebass'
import styled, { ThemeContext } from 'styled-components'
import { useActiveWeb3React } from '../../hooks/web3'
import { HideSmall, LinkStyledButton, TYPE } from '../../theme'
import AppBody from '../AppBody'
import Row, { AutoRow, RowFixed } from '../../components/Row'

const StyledInfo = styled(Info)`
  opacity: 0.4;
  color: ${({ theme }) => theme.text1};
  height: 16px;
  width: 16px;
  :hover {
    opacity: 0.8;
  }
`

export default function Market({ history }: RouteComponentProps) {
  const { account } = useActiveWeb3React()
  const theme = useContext(ThemeContext)
  // swap state
  return (
    <>
      <AppBody>
        <Row style={{ justifyContent: 'center' }}></Row>
      </AppBody>
    </>
  )
}
