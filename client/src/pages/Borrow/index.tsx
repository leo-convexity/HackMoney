import React, { useContext } from 'react'
import { RouteComponentProps } from 'react-router-dom'
import { ThemeContext } from 'styled-components'
import { useActiveWeb3React } from '../../hooks/web3'
import AppBody from '../AppBody'
import Row from '../../components/Row'

export default function Borrow({ history }: RouteComponentProps) {
  const { account } = useActiveWeb3React()
  const theme = useContext(ThemeContext)
  console.log('Current account: ' + account)
  console.log('Theme: ' + JSON.stringify(theme))
  console.log('History: ' + JSON.stringify(history))
  return (
    <>
      <AppBody>
        <Row style={{ justifyContent: 'center' }}></Row>
      </AppBody>
    </>
  )
}
