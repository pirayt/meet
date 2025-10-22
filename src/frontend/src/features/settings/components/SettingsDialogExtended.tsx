import { Dialog, type DialogProps } from '@/primitives'
import { Tab, Tabs, TabList } from '@/primitives/Tabs.tsx'
import { css } from '@/styled-system/css'
import { text } from '@/primitives/Text.tsx'
import { Heading } from 'react-aria-components'
import { useTranslation } from 'react-i18next'
import {
  RiAccountCircleLine,
  RiNotification3Line,
  RiSettings3Line,
  RiSpeakerLine,
  RiVideoOnLine,
} from '@remixicon/react'
import { AccountTab } from './tabs/AccountTab'
import { NotificationsTab } from './tabs/NotificationsTab'
import { GeneralTab } from './tabs/GeneralTab'
import { AudioTab } from './tabs/AudioTab'
import { VideoTab } from './tabs/VideoTab'
import { useRef } from 'react'
import { useMediaQuery } from '@/features/rooms/livekit/hooks/useMediaQuery'
import { SettingsDialogExtendedKey } from '@/features/settings/type'

const getTabsStyle = (isMobile: boolean) =>
  css({
    height: isMobile ? '100%' : '650px',
    width: isMobile ? '100%' : '800px',
    minWidth: isMobile ? '100%' : '800px',
    maxWidth: isMobile ? '100%' : '800px',
    minHeight: isMobile ? '100%' : '650px',
    maxHeight: isMobile ? '100%' : '650px',
    marginY: isMobile ? '0' : '-1rem',
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'row',
    flexShrink: 0,
  })

const getTabListContainerStyle = (isMobile: boolean) =>
  css({
    display: 'flex',
    flexDirection: 'column',
    borderRight: '1px solid lightGray', // fixme poor color management
    paddingY: isMobile ? '0.5rem' : '1rem',
    paddingRight: isMobile ? '0.5rem' : '1.5rem',
  })

const getTabPanelContainerStyle = (isMobile: boolean, isWideScreen: boolean) =>
  css({
    display: 'flex',
    flexGrow: '1',
    marginTop: isWideScreen ? '3.5rem' : isMobile ? '0.5rem' : '3.5rem',
    minWidth: 0,
    overflow: 'auto',
  })

export type SettingsDialogExtended = Pick<
  DialogProps,
  'isOpen' | 'onOpenChange'
> & {
  defaultSelectedTab?: SettingsDialogExtendedKey
}

export const SettingsDialogExtended = (props: SettingsDialogExtended) => {
  // display only icon on small screen
  const { t } = useTranslation('settings')

  const dialogEl = useRef<HTMLDivElement>(null)
  const isWideScreen = useMediaQuery('(min-width: 800px)') // fixme - hardcoded 50rem in pixel
  const isMobile = !useMediaQuery('(min-width: 768px)')

  // Set default tab to ACCOUNT if not provided to prevent collapsed state
  const defaultTab = props.defaultSelectedTab || SettingsDialogExtendedKey.ACCOUNT

  return (
    <Dialog innerRef={dialogEl} {...props} role="dialog" type="flex">
      <Tabs
        orientation="vertical"
        className={getTabsStyle(isMobile)}
        defaultSelectedKey={defaultTab}
      >
        <div
          className={getTabListContainerStyle(isMobile)}
          style={{
            flex: isWideScreen ? '0 0 16rem' : '0 0 4rem',
            paddingTop: !isWideScreen
              ? isMobile
                ? '0.5rem'
                : '64px'
              : undefined,
            paddingRight: !isWideScreen ? '0.5rem' : undefined,
          }}
        >
          {isWideScreen && (
            <Heading slot="title" level={1} className={text({ variant: 'h1' })}>
              {t('dialog.heading')}
            </Heading>
          )}
          <TabList border={false}>
            <Tab icon highlight id={SettingsDialogExtendedKey.ACCOUNT}>
              <RiAccountCircleLine />
              {isWideScreen && t(`tabs.${SettingsDialogExtendedKey.ACCOUNT}`)}
            </Tab>
            <Tab icon highlight id={SettingsDialogExtendedKey.AUDIO}>
              <RiSpeakerLine />
              {isWideScreen && t(`tabs.${SettingsDialogExtendedKey.AUDIO}`)}
            </Tab>
            <Tab icon highlight id={SettingsDialogExtendedKey.VIDEO}>
              <RiVideoOnLine />
              {isWideScreen && t(`tabs.${SettingsDialogExtendedKey.VIDEO}`)}
            </Tab>
            <Tab icon highlight id={SettingsDialogExtendedKey.GENERAL}>
              <RiSettings3Line />
              {isWideScreen && t(`tabs.${SettingsDialogExtendedKey.GENERAL}`)}
            </Tab>
            <Tab icon highlight id={SettingsDialogExtendedKey.NOTIFICATIONS}>
              <RiNotification3Line />
              {isWideScreen &&
                t(`tabs.${SettingsDialogExtendedKey.NOTIFICATIONS}`)}
            </Tab>
          </TabList>
        </div>
        <div className={getTabPanelContainerStyle(isMobile, isWideScreen)}>
          <AccountTab
            id={SettingsDialogExtendedKey.ACCOUNT}
            onOpenChange={props.onOpenChange}
          />
          <AudioTab id={SettingsDialogExtendedKey.AUDIO} />
          <VideoTab id={SettingsDialogExtendedKey.VIDEO} />
          <GeneralTab id={SettingsDialogExtendedKey.GENERAL} />
          <NotificationsTab id={SettingsDialogExtendedKey.NOTIFICATIONS} />
        </div>
      </Tabs>
    </Dialog>
  )
}
